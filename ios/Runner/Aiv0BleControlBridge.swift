import CoreBluetooth
import Flutter
import Foundation

struct Aiv0DuplicatePacketFilter {
  static let windowMilliseconds: TimeInterval = 750

  private var lastPacketIdentity: String?
  private var lastPacketUptimeMilliseconds: TimeInterval?
  private(set) var duplicateCount = 0

  mutating func register(
    bytes: [UInt8],
    uptimeMilliseconds: TimeInterval
  ) -> Bool {
    let packetIdentity = Self.identity(for: bytes)
    let isDuplicate = lastPacketIdentity == packetIdentity
      && lastPacketUptimeMilliseconds.map {
        uptimeMilliseconds - $0 <= Self.windowMilliseconds
      } == true
    if isDuplicate {
      duplicateCount += 1
    }
    lastPacketIdentity = packetIdentity
    lastPacketUptimeMilliseconds = uptimeMilliseconds
    return isDuplicate
  }

  /// H20 firmware 1.0.0 can emit a burst for one physical MAIN press while
  /// incrementing sequence and uptime in every packet. Those transport fields
  /// must not turn the burst into multiple app actions. The current firmware
  /// exposes only one MAIN action (byte 3 == 0x01), without long-press/release.
  private static func identity(for bytes: [UInt8]) -> String {
    if bytes.count == 12,
      bytes[0] == 0x01,
      bytes[1] == 0x01,
      bytes[3] == 0x01
    {
      return String(format: "H20:%02X:%02X", bytes[0], bytes[1])
    }
    return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
  }

  mutating func resetWindow() {
    lastPacketUptimeMilliseconds = nil
  }
}

/// iOS implementation of the same AIV0/H20 BLE control contract used by the
/// Android bridge. Audio remains on HFP; BLE carries MAIN button notifications,
/// battery/firmware diagnostics, and the optional APP State packet only.
final class Aiv0BleControlBridge: NSObject, FlutterStreamHandler {
  private enum ProtocolUUID {
    static let controlService = CBUUID(string: "9E3B0001-4A7C-4D6F-8B21-5C17A2D94010")
    static let buttonEvent = CBUUID(string: "9E3B0002-4A7C-4D6F-8B21-5C17A2D94010")
    static let appState = CBUUID(string: "9E3B0003-4A7C-4D6F-8B21-5C17A2D94010")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let deviceInformationService = CBUUID(string: "180A")
    static let firmwareRevision = CBUUID(string: "2A26")
  }

  private struct DiscoveredDevice {
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var likely: Bool
    var advertisesControlService: Bool

    var map: [String: Any] {
      [
        "id": peripheral.identifier.uuidString,
        "name": name,
        "rssi": rssi,
        "isLikelyAiv0": likely,
        "advertisesControlService": advertisesControlService,
      ]
    }
  }

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private var central: CBCentralManager?
  private var discoveredDevices: [UUID: DiscoveredDevice] = [:]
  private var connectedPeripheral: CBPeripheral?
  private var buttonCharacteristic: CBCharacteristic?
  private var stateCharacteristic: CBCharacteristic?
  private var pendingPermissionResults: [FlutterResult] = []
  private var pendingScanResult: FlutterResult?
  private var pendingConnectResult: FlutterResult?
  private var pendingWriteResult: FlutterResult?
  private var scanTimeoutWorkItem: DispatchWorkItem?
  private var connectTimeoutWorkItem: DispatchWorkItem?
  private var reconnectWorkItem: DispatchWorkItem?
  private var phase = "idle"
  private var message: String?
  private var writeMode: String?
  private var batteryPercent: Int?
  private var firmwareRevision: String?
  private var lastRawHex: String?
  private var duplicatePacketFilter = Aiv0DuplicatePacketFilter()
  private var packetCount = 0
  private var invalidPacketCount = 0
  private var reconnectCount = 0
  private var manualDisconnect = false
  private var disposed = false

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: "ailingo_aiv0_ble_control",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "ailingo_aiv0_ble_control/events",
      binaryMessenger: messenger
    )
    super.init()
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    eventChannel.setStreamHandler(self)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !disposed || call.method == "dispose" else {
      result(FlutterError(code: "BLE_DISPOSED", message: "Cầu nối BLE đã đóng.", details: nil))
      return
    }
    switch call.method {
    case "initialize":
      // Do not instantiate CBCentralManager here. iOS may show its Bluetooth
      // prompt at that point; the app first presents the parental disclosure.
      result(snapshot())
      emitStatus()
    case "requestPermissions":
      requestPermissions(result)
    case "scan":
      let arguments = call.arguments as? [String: Any]
      let requested = (arguments?["timeoutMs"] as? NSNumber)?.intValue ?? 8_000
      scan(timeoutMilliseconds: min(max(requested, 2_000), 15_000), result: result)
    case "connect":
      let arguments = call.arguments as? [String: Any]
      connect(deviceId: arguments?["deviceId"] as? String, result: result)
    case "disconnect":
      disconnect(result)
    case "sendAppState":
      let arguments = call.arguments as? [String: Any]
      sendAppState(arguments?["bytes"], result: result)
    case "status":
      result(snapshot())
    case "dispose":
      dispose()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func ensureCentral() -> CBCentralManager {
    if let central { return central }
    let manager = CBCentralManager(
      delegate: self,
      queue: .main,
      options: [CBCentralManagerOptionShowPowerAlertKey: true]
    )
    central = manager
    return manager
  }

  private func requestPermissions(_ result: @escaping FlutterResult) {
    switch CBManager.authorization {
    case .allowedAlways:
      let manager = ensureCentral()
      if manager.state == .unknown || manager.state == .resetting {
        pendingPermissionResults.append(result)
      } else {
        result(true)
      }
    case .denied, .restricted:
      phase = "error"
      message = "Quyền Bluetooth đã bị từ chối trong Cài đặt iOS."
      emitStatus()
      result(false)
    case .notDetermined:
      pendingPermissionResults.append(result)
      _ = ensureCentral()
    @unknown default:
      result(false)
    }
  }

  private func scan(timeoutMilliseconds: Int, result: @escaping FlutterResult) {
    guard pendingScanResult == nil else {
      result(FlutterError(code: "SCAN_IN_PROGRESS", message: "Đang quét Bluetooth.", details: nil))
      return
    }
    guard let manager = readyCentral(result) else { return }
    discoveredDevices.removeAll()
    pendingScanResult = result
    phase = "scanning"
    message = nil
    emitStatus()
    manager.scanForPeripherals(
      withServices: nil,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
    let workItem = DispatchWorkItem { [weak self] in self?.finishScan() }
    scanTimeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(timeoutMilliseconds),
      execute: workItem
    )
  }

  private func finishScan() {
    scanTimeoutWorkItem?.cancel()
    scanTimeoutWorkItem = nil
    central?.stopScan()
    guard let result = pendingScanResult else { return }
    pendingScanResult = nil
    let devices = discoveredDevices.values.sorted {
      if $0.likely != $1.likely { return $0.likely && !$1.likely }
      return $0.rssi > $1.rssi
    }
    phase = stateCharacteristic == nil ? "idle" : "connected"
    message = devices.isEmpty ? "Không tìm thấy H20/AIV0." : nil
    emitStatus()
    result(devices.map(\.map))
  }

  private func connect(deviceId: String?, result: @escaping FlutterResult) {
    guard let idText = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines),
      let identifier = UUID(uuidString: idText)
    else {
      result(FlutterError(code: "INVALID_DEVICE", message: "Thiếu mã thiết bị BLE.", details: nil))
      return
    }
    guard pendingConnectResult == nil else {
      result(FlutterError(code: "CONNECT_IN_PROGRESS", message: "Đang kết nối H20.", details: nil))
      return
    }
    guard let manager = readyCentral(result) else { return }
    finishScanIfNeeded()
    let peripheral = discoveredDevices[identifier]?.peripheral
      ?? manager.retrievePeripherals(withIdentifiers: [identifier]).first
    guard let peripheral else {
      result(FlutterError(
        code: "DEVICE_NOT_FOUND",
        message: "Không tìm thấy H20 đã lưu. Hãy quét lại thiết bị.",
        details: nil
      ))
      return
    }
    resetCharacteristics()
    manualDisconnect = false
    connectedPeripheral = peripheral
    peripheral.delegate = self
    pendingConnectResult = result
    phase = "connecting"
    message = "Đang kết nối BLE Control H20…"
    emitStatus()
    manager.connect(peripheral, options: nil)
    scheduleConnectTimeout()
  }

  private func disconnect(_ result: @escaping FlutterResult) {
    manualDisconnect = true
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    connectTimeoutWorkItem?.cancel()
    connectTimeoutWorkItem = nil
    failPendingConnect(code: "CONNECT_CANCELLED", message: "Đã hủy kết nối H20.")
    if let peripheral = connectedPeripheral {
      central?.cancelPeripheralConnection(peripheral)
    }
    resetCharacteristics()
    connectedPeripheral = nil
    phase = "idle"
    message = nil
    emitStatus()
    result(nil)
  }

  private func sendAppState(_ rawBytes: Any?, result: @escaping FlutterResult) {
    guard pendingWriteResult == nil else {
      result(FlutterError(code: "WRITE_IN_PROGRESS", message: "Đang gửi trạng thái trước đó.", details: nil))
      return
    }
    guard let peripheral = connectedPeripheral, let characteristic = stateCharacteristic else {
      result(FlutterError(code: "NOT_CONNECTED", message: "BLE Control H20 chưa kết nối.", details: nil))
      return
    }
    let numbers = rawBytes as? [NSNumber]
      ?? (rawBytes as? [Int])?.map { NSNumber(value: $0) }
    guard let numbers, !numbers.isEmpty else {
      result(FlutterError(code: "INVALID_PACKET", message: "APP State packet rỗng.", details: nil))
      return
    }
    let data = Data(numbers.map { UInt8(truncating: $0) })
    if characteristic.properties.contains(.write) {
      pendingWriteResult = result
      peripheral.writeValue(data, for: characteristic, type: .withResponse)
    } else if characteristic.properties.contains(.writeWithoutResponse) {
      peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
      result(nil)
    } else {
      result(FlutterError(code: "WRITE_UNSUPPORTED", message: "APP State không cho phép ghi.", details: nil))
    }
  }

  private func readyCentral(_ result: FlutterResult) -> CBCentralManager? {
    guard CBManager.authorization == .allowedAlways else {
      result(FlutterError(code: "PERMISSION_REQUIRED", message: "Cần cấp quyền Bluetooth trước.", details: nil))
      return nil
    }
    let manager = ensureCentral()
    switch manager.state {
    case .poweredOn:
      return manager
    case .poweredOff:
      result(FlutterError(code: "BLUETOOTH_DISABLED", message: "Bluetooth đang tắt.", details: nil))
    case .unsupported:
      result(FlutterError(code: "BLE_UNSUPPORTED", message: "Thiết bị iOS không hỗ trợ BLE.", details: nil))
    case .unauthorized:
      result(FlutterError(code: "PERMISSION_REQUIRED", message: "iOS chưa cho phép Bluetooth.", details: nil))
    default:
      result(FlutterError(code: "BLUETOOTH_NOT_READY", message: "Bluetooth đang khởi tạo, hãy thử lại.", details: nil))
    }
    return nil
  }

  private func scheduleConnectTimeout() {
    connectTimeoutWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self, self.pendingConnectResult != nil else { return }
      if let peripheral = self.connectedPeripheral {
        self.central?.cancelPeripheralConnection(peripheral)
      }
      self.phase = "error"
      self.message = "Hết thời gian xác minh dịch vụ BLE Control H20."
      self.emitStatus()
      self.failPendingConnect(code: "CONNECT_TIMEOUT", message: self.message!)
    }
    connectTimeoutWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: item)
  }

  private func completeConnection() {
    connectTimeoutWorkItem?.cancel()
    connectTimeoutWorkItem = nil
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    reconnectCount = 0
    phase = "connected"
    message = "BLE Control H20 đã kết nối."
    emitStatus()
    let result = pendingConnectResult
    pendingConnectResult = nil
    result?(nil)
  }

  private func failPendingConnect(code: String, message: String) {
    let result = pendingConnectResult
    pendingConnectResult = nil
    result?(FlutterError(code: code, message: message, details: nil))
  }

  private func scheduleReconnect(_ peripheral: CBPeripheral) {
    guard !manualDisconnect, !disposed, reconnectCount < 3 else {
      phase = "error"
      message = "Kết nối BLE Control H20 đã mất."
      emitStatus()
      return
    }
    reconnectCount += 1
    phase = "reconnecting"
    message = "Đang kết nối lại H20 (lần \(reconnectCount)/3)…"
    emitStatus()
    let delay = min(pow(2.0, Double(reconnectCount - 1)), 4.0)
    let item = DispatchWorkItem { [weak self, weak peripheral] in
      guard let self, let peripheral, !self.manualDisconnect, !self.disposed else { return }
      self.resetCharacteristics()
      peripheral.delegate = self
      self.central?.connect(peripheral, options: nil)
    }
    reconnectWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
  }

  private func validateControlCharacteristics() {
    guard let button = buttonCharacteristic, let state = stateCharacteristic else {
      phase = "error"
      message = "H20 thiếu characteristic MAIN hoặc APP State."
      emitStatus()
      failPendingConnect(code: "PROTOCOL_MISMATCH", message: message!)
      if let peripheral = connectedPeripheral { central?.cancelPeripheralConnection(peripheral) }
      return
    }
    let canNotify = button.properties.contains(.notify) || button.properties.contains(.indicate)
    let canWrite = state.properties.contains(.write) || state.properties.contains(.writeWithoutResponse)
    guard canNotify, canWrite else {
      phase = "error"
      message = "Characteristic BLE Control H20 không đúng quyền Notify/Write."
      emitStatus()
      failPendingConnect(code: "PROTOCOL_MISMATCH", message: message!)
      return
    }
    writeMode = state.properties.contains(.write) ? "WRITE" : "WRITE_NO_RESPONSE"
    connectedPeripheral?.setNotifyValue(true, for: button)
  }

  private func resetCharacteristics() {
    buttonCharacteristic = nil
    stateCharacteristic = nil
    writeMode = nil
    batteryPercent = nil
    firmwareRevision = nil
    duplicatePacketFilter.resetWindow()
  }

  private func finishScanIfNeeded() {
    guard pendingScanResult != nil else { return }
    finishScan()
  }

  private func snapshot() -> [String: Any] {
    var value: [String: Any] = [
      "type": "status",
      "phase": phase,
      "packetCount": packetCount,
      "invalidPacketCount": invalidPacketCount,
      "duplicatePacketCount": duplicatePacketFilter.duplicateCount,
      "reconnectCount": reconnectCount,
    ]
    if let peripheral = connectedPeripheral {
      value["deviceId"] = peripheral.identifier.uuidString
      value["deviceName"] = peripheral.name ?? discoveredDevices[peripheral.identifier]?.name ?? "H20"
    }
    if let message { value["message"] = message }
    if let writeMode { value["writeMode"] = writeMode }
    if let batteryPercent { value["batteryPercent"] = batteryPercent }
    if let firmwareRevision { value["firmwareRevision"] = firmwareRevision }
    if let lastRawHex { value["lastRawHex"] = lastRawHex }
    return value
  }

  private func emitStatus() {
    guard !disposed else { return }
    eventSink?(snapshot())
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    events(snapshot())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    scanTimeoutWorkItem?.cancel()
    connectTimeoutWorkItem?.cancel()
    reconnectWorkItem?.cancel()
    central?.stopScan()
    if let peripheral = connectedPeripheral { central?.cancelPeripheralConnection(peripheral) }
    pendingPermissionResults.forEach { $0(false) }
    pendingPermissionResults.removeAll()
    pendingScanResult?(FlutterError(code: "BLE_DISPOSED", message: "Đã đóng cầu nối BLE.", details: nil))
    pendingScanResult = nil
    failPendingConnect(code: "BLE_DISPOSED", message: "Đã đóng cầu nối BLE.")
    pendingWriteResult?(FlutterError(code: "BLE_DISPOSED", message: "Đã đóng cầu nối BLE.", details: nil))
    pendingWriteResult = nil
    eventSink = nil
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
    central?.delegate = nil
    central = nil
  }
}

extension Aiv0BleControlBridge: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      phase = stateCharacteristic == nil ? "idle" : "connected"
      message = nil
    case .poweredOff:
      phase = "error"
      message = "Bluetooth đang tắt."
    case .unauthorized:
      phase = "error"
      message = "iOS chưa cho phép Bluetooth."
    case .unsupported:
      phase = "disabled"
      message = "Thiết bị iOS không hỗ trợ BLE."
    case .resetting:
      phase = "idle"
      message = "Bluetooth đang khởi động lại…"
    case .unknown:
      break
    @unknown default:
      phase = "error"
      message = "Trạng thái Bluetooth không xác định."
    }
    if CBManager.authorization != .notDetermined && !pendingPermissionResults.isEmpty {
      let granted = CBManager.authorization == .allowedAlways
      let results = pendingPermissionResults
      pendingPermissionResults.removeAll()
      results.forEach { $0(granted) }
    }
    emitStatus()
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    let name = advertisedName?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? "H20"
    let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    let advertisesControl = services.contains(ProtocolUUID.controlService)
    let lowerName = name.lowercased()
    let likely = advertisesControl || lowerName.contains("h20")
      || lowerName.contains("aiv0") || lowerName.contains("innotrik")
    let current = discoveredDevices[peripheral.identifier]
    if current == nil || RSSI.intValue > current!.rssi {
      discoveredDevices[peripheral.identifier] = DiscoveredDevice(
        peripheral: peripheral,
        name: name.isEmpty ? "H20" : name,
        rssi: RSSI.intValue,
        likely: likely,
        advertisesControlService: advertisesControl
      )
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    connectedPeripheral = peripheral
    peripheral.delegate = self
    phase = "connecting"
    message = "Đang xác minh dịch vụ BLE Control…"
    emitStatus()
    peripheral.discoverServices([
      ProtocolUUID.controlService,
      ProtocolUUID.batteryService,
      ProtocolUUID.deviceInformationService,
    ])
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    phase = "error"
    message = "Không kết nối được H20: \(error?.localizedDescription ?? "không rõ lỗi")"
    emitStatus()
    failPendingConnect(code: "CONNECT_FAILED", message: message!)
    scheduleReconnect(peripheral)
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    resetCharacteristics()
    if manualDisconnect || disposed {
      phase = "idle"
      message = nil
      emitStatus()
      return
    }
    scheduleReconnect(peripheral)
  }
}

extension Aiv0BleControlBridge: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil else {
      failDiscovery("Không đọc được dịch vụ BLE: \(error!.localizedDescription)")
      return
    }
    let services = peripheral.services ?? []
    guard services.contains(where: { $0.uuid == ProtocolUUID.controlService }) else {
      failDiscovery("Thiết bị không có dịch vụ BLE Control 9E3B0001.")
      return
    }
    for service in services {
      switch service.uuid {
      case ProtocolUUID.controlService:
        peripheral.discoverCharacteristics(
          [ProtocolUUID.buttonEvent, ProtocolUUID.appState],
          for: service
        )
      case ProtocolUUID.batteryService:
        peripheral.discoverCharacteristics([ProtocolUUID.batteryLevel], for: service)
      case ProtocolUUID.deviceInformationService:
        peripheral.discoverCharacteristics([ProtocolUUID.firmwareRevision], for: service)
      default:
        break
      }
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard error == nil else {
      if service.uuid == ProtocolUUID.controlService {
        failDiscovery("Không đọc được characteristic BLE Control: \(error!.localizedDescription)")
      }
      return
    }
    for characteristic in service.characteristics ?? [] {
      switch characteristic.uuid {
      case ProtocolUUID.buttonEvent:
        buttonCharacteristic = characteristic
      case ProtocolUUID.appState:
        stateCharacteristic = characteristic
      case ProtocolUUID.batteryLevel:
        peripheral.readValue(for: characteristic)
      case ProtocolUUID.firmwareRevision:
        peripheral.readValue(for: characteristic)
      default:
        break
      }
    }
    if service.uuid == ProtocolUUID.controlService { validateControlCharacteristics() }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard characteristic.uuid == ProtocolUUID.buttonEvent else { return }
    guard error == nil, characteristic.isNotifying else {
      failDiscovery("Không bật được thông báo MAIN của H20.")
      return
    }
    completeConnection()
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard error == nil, let data = characteristic.value else {
      if characteristic.uuid == ProtocolUUID.buttonEvent {
        invalidPacketCount += 1
        emitStatus()
      }
      return
    }
    if characteristic.uuid == ProtocolUUID.buttonEvent {
      let bytes = [UInt8](data)
      packetCount += 1
      if bytes.count != 12 { invalidPacketCount += 1 }
      let rawHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
      let duplicate = duplicatePacketFilter.register(
        bytes: bytes,
        uptimeMilliseconds: ProcessInfo.processInfo.systemUptime * 1_000
      )
      lastRawHex = rawHex
      eventSink?([
        "type": "button",
        "bytes": bytes.map { Int($0) },
        "deviceId": peripheral.identifier.uuidString,
        "duplicate": duplicate,
        "receivedAtEpochMs": Int(Date().timeIntervalSince1970 * 1_000),
      ])
      emitStatus()
    } else if characteristic.uuid == ProtocolUUID.batteryLevel, let first = data.first {
      batteryPercent = min(max(Int(first), 0), 100)
      emitStatus()
    } else if characteristic.uuid == ProtocolUUID.firmwareRevision {
      firmwareRevision = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      emitStatus()
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didWriteValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard characteristic.uuid == ProtocolUUID.appState else { return }
    let result = pendingWriteResult
    pendingWriteResult = nil
    if let error {
      result?(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
    } else {
      result?(nil)
    }
  }

  private func failDiscovery(_ text: String) {
    phase = "error"
    message = text
    emitStatus()
    failPendingConnect(code: "PROTOCOL_MISMATCH", message: text)
    if let peripheral = connectedPeripheral { central?.cancelPeripheralConnection(peripheral) }
  }
}
