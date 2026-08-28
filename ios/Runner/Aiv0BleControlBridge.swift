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

struct Aiv0ReconnectPolicy {
  static let maxAttempts = 3
  static let attemptTimeoutSeconds: TimeInterval = 10

  static func delaySeconds(forAttempt attempt: Int) -> TimeInterval {
    min(pow(2.0, Double(max(attempt, 1) - 1)), 4.0)
  }

  static func shouldDeferReconnect(
    mainTurnActive: Bool
  ) -> Bool {
    mainTurnActive
  }

  static func shouldDeferNotificationMaintenance(
    mainTurnActive: Bool,
    speechCaptureActive: Bool,
    hfpRouteActive: Bool
  ) -> Bool {
    // HFP is the selected mic/loa route, not a reason to starve BLE forever.
    // Only a live MAIN turn or PCM capture owns the short critical section.
    _ = hfpRouteActive
    return mainTurnActive || speechCaptureActive
  }
}

enum Aiv0MainNotificationRefreshStep: Equatable {
  case reconnect
  case rediscover
  case disable
  case enable
  case complete
}

/// H20 can keep its GATT connection alive while silently dropping the MAIN
/// notification subscription when iOS enters and leaves the HFP/SCO voice
/// profile. CoreBluetooth does not emit `didDisconnectPeripheral` in that
/// state, so a normal reconnect policy cannot recover later physical presses.
struct Aiv0MainNotificationRefreshPolicy {
  static func nextStep(
    peripheralConnected: Bool,
    hasButtonCharacteristic: Bool,
    refreshInProgress: Bool,
    isNotifying: Bool
  ) -> Aiv0MainNotificationRefreshStep {
    guard peripheralConnected else { return .reconnect }
    guard hasButtonCharacteristic else { return .rediscover }
    if refreshInProgress {
      return isNotifying ? .complete : .enable
    }
    // CoreBluetooth can keep reporting `isNotifying == true` after H20 silently
    // drops the notification while its radio switches to HFP/SCO. A controlled
    // disable -> enable cycle is therefore required to re-arm physical MAIN.
    return isNotifying ? .disable : .enable
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
  private let audioSessionCoordinator: IOSAudioSessionCoordinator
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
  private var reconnectTimeoutWorkItem: DispatchWorkItem?
  private var notificationRefreshWorkItem: DispatchWorkItem?
  private var notificationRefreshTimeoutWorkItem: DispatchWorkItem?
  private weak var deferredReconnectPeripheral: CBPeripheral?
  private var notificationRefreshInProgress = false
  private var notificationValidationPending = false
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

  init(
    messenger: FlutterBinaryMessenger,
    audioSessionCoordinator: IOSAudioSessionCoordinator
  ) {
    self.audioSessionCoordinator = audioSessionCoordinator
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
    audioSessionCoordinator.onMainTurnEnded = { [weak self] in
      guard let self else { return }
      if let peripheral = self.deferredReconnectPeripheral {
        self.deferredReconnectPeripheral = nil
        self.audioSessionCoordinator.trace(
          stage: "ble_reconnect_resumed",
          caller: "Aiv0BleControlBridge"
        )
        self.scheduleReconnect(peripheral)
        return
      }
      // Re-arm MAIN once more when the assistant turn fully ends. H20 can
      // silently lose notifications across an SCO transition while
      // CoreBluetooth continues to report `isNotifying == true`.
      self.scheduleMainNotificationRefresh()
    }
    audioSessionCoordinator.onAudioSessionReleased = { [weak self] in
      self?.resumeDeferredBluetoothRecovery()
    }
    audioSessionCoordinator.onSpeechCaptureEnded = { [weak self] in
      self?.scheduleMainNotificationRefresh()
    }
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
    cancelReconnectTasks()
    reconnectCount = 0
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
    cancelReconnectTasks()
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
    cancelReconnectTasks()
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
    if shouldDeferBluetoothReconnect() {
      deferredReconnectPeripheral = peripheral
      phase = "reconnecting"
      message = "BLE H20 tạm chờ đến khi lượt MAIN kết thúc; HFP không bị thay đổi."
      audioSessionCoordinator.trace(
        stage: "ble_reconnect_deferred",
        caller: "Aiv0BleControlBridge.scheduleReconnect"
      )
      emitStatus()
      return
    }
    guard reconnectWorkItem == nil, reconnectTimeoutWorkItem == nil else {
      return
    }
    guard !manualDisconnect, !disposed,
      reconnectCount < Aiv0ReconnectPolicy.maxAttempts
    else {
      phase = "error"
      message = "Kết nối BLE Control H20 đã mất."
      emitStatus()
      return
    }
    reconnectCount += 1
    let attempt = reconnectCount
    phase = "reconnecting"
    message = "Đang kết nối lại H20 (lần \(attempt)/\(Aiv0ReconnectPolicy.maxAttempts))…"
    emitStatus()
    let delay = Aiv0ReconnectPolicy.delaySeconds(forAttempt: attempt)
    let item = DispatchWorkItem { [weak self, weak peripheral] in
      guard let self, let peripheral, !self.manualDisconnect, !self.disposed else { return }
      self.reconnectWorkItem = nil
      if self.shouldDeferBluetoothReconnect() {
        self.deferredReconnectPeripheral = peripheral
        self.audioSessionCoordinator.trace(
          stage: "ble_reconnect_deferred",
          caller: "Aiv0BleControlBridge.reconnectWorkItem"
        )
        return
      }
      self.resetCharacteristics()
      peripheral.delegate = self
      self.central?.connect(peripheral, options: nil)
      self.scheduleReconnectTimeout(peripheral, attempt: attempt)
    }
    reconnectWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
  }

  private func scheduleReconnectTimeout(_ peripheral: CBPeripheral, attempt: Int) {
    reconnectTimeoutWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self, weak peripheral] in
      guard let self, let peripheral,
        !self.manualDisconnect,
        !self.disposed,
        self.reconnectCount == attempt,
        self.stateCharacteristic == nil
      else { return }
      self.reconnectTimeoutWorkItem = nil
      if self.shouldDeferBluetoothReconnect() {
        self.deferredReconnectPeripheral = peripheral
        self.audioSessionCoordinator.trace(
          stage: "ble_reconnect_deferred",
          caller: "Aiv0BleControlBridge.reconnectTimeout"
        )
        return
      }
      self.phase = "reconnecting"
      self.message = "H20 chưa phản hồi ở lần \(attempt); đang thử lại…"
      self.emitStatus()
      self.central?.cancelPeripheralConnection(peripheral)
      self.scheduleReconnect(peripheral)
    }
    reconnectTimeoutWorkItem = item
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Aiv0ReconnectPolicy.attemptTimeoutSeconds,
      execute: item
    )
  }

  private func cancelReconnectTasks() {
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    reconnectTimeoutWorkItem?.cancel()
    reconnectTimeoutWorkItem = nil
  }

  private func shouldDeferBluetoothReconnect() -> Bool {
    Aiv0ReconnectPolicy.shouldDeferReconnect(
      mainTurnActive: audioSessionCoordinator.isMainTurnActive
    )
  }

  private func shouldDeferNotificationMaintenance() -> Bool {
    Aiv0ReconnectPolicy.shouldDeferNotificationMaintenance(
      mainTurnActive: audioSessionCoordinator.isMainTurnActive,
      speechCaptureActive: audioSessionCoordinator.isSpeechCaptureActive,
      hfpRouteActive: audioSessionCoordinator.hasTwoWayHfpRoute()
    )
  }

  private func resumeDeferredBluetoothRecovery() {
    guard !disposed else { return }
    if let peripheral = deferredReconnectPeripheral {
      deferredReconnectPeripheral = nil
      audioSessionCoordinator.trace(
        stage: "ble_reconnect_resumed_after_audio_release",
        caller: "Aiv0BleControlBridge"
      )
      scheduleReconnect(peripheral)
      return
    }
    if notificationValidationPending {
      notificationValidationPending = false
      scheduleMainNotificationRefresh()
    }
  }

  private func scheduleMainNotificationRefresh() {
    if shouldDeferNotificationMaintenance() {
      notificationValidationPending = true
      audioSessionCoordinator.trace(
        stage: "ble_main_notification_validation_deferred",
        caller: "Aiv0BleControlBridge"
      )
      return
    }
    if notificationRefreshInProgress {
      notificationValidationPending = true
      audioSessionCoordinator.trace(
        stage: "ble_main_notification_refresh_coalesced",
        caller: "Aiv0BleControlBridge"
      )
      return
    }
    notificationValidationPending = false
    notificationRefreshWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self, !self.disposed else { return }
      self.notificationRefreshWorkItem = nil
      if self.shouldDeferNotificationMaintenance() {
        self.notificationValidationPending = true
        return
      }
      if self.notificationRefreshInProgress {
        self.notificationValidationPending = true
        return
      }
      self.notificationValidationPending = false
      self.refreshMainNotificationSubscription()
    }
    notificationRefreshWorkItem = item
    // Give AVAudioEngine time to remove its input tap. HFP may stay selected;
    // BLE notification maintenance is independent once capture has ended.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
  }

  private func scheduleMainNotificationRefreshTimeout(_ peripheral: CBPeripheral) {
    notificationRefreshTimeoutWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self, weak peripheral] in
      guard let self, let peripheral,
        self.notificationRefreshInProgress,
        !self.disposed
      else { return }
      self.notificationRefreshTimeoutWorkItem = nil
      self.notificationRefreshInProgress = false
      if self.shouldDeferNotificationMaintenance() {
        self.notificationValidationPending = true
        self.audioSessionCoordinator.trace(
          stage: "ble_main_notification_timeout_deferred",
          caller: "Aiv0BleControlBridge"
        )
        return
      }
      self.audioSessionCoordinator.trace(
        stage: "ble_main_notification_refresh_timeout",
        caller: "Aiv0BleControlBridge"
      )
      if peripheral.state == .connected || peripheral.state == .connecting {
        self.central?.cancelPeripheralConnection(peripheral)
      } else {
        self.scheduleReconnect(peripheral)
      }
    }
    notificationRefreshTimeoutWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
  }

  private func refreshMainNotificationSubscription() {
    guard let peripheral = connectedPeripheral else { return }
    let step = Aiv0MainNotificationRefreshPolicy.nextStep(
      peripheralConnected: peripheral.state == .connected,
      hasButtonCharacteristic: buttonCharacteristic != nil,
      refreshInProgress: notificationRefreshInProgress,
      isNotifying: buttonCharacteristic?.isNotifying ?? false
    )
    audioSessionCoordinator.trace(
      stage: "ble_main_notification_refresh",
      caller: "Aiv0BleControlBridge",
      message: String(describing: step)
    )
    switch step {
    case .reconnect:
      notificationRefreshInProgress = false
      scheduleReconnect(peripheral)
    case .rediscover:
      notificationRefreshInProgress = false
      phase = "connecting"
      message = "Đang khôi phục nút MAIN H20…"
      emitStatus()
      peripheral.discoverServices([
        ProtocolUUID.controlService,
        ProtocolUUID.batteryService,
        ProtocolUUID.deviceInformationService,
      ])
    case .disable:
      guard let buttonCharacteristic else { return }
      notificationRefreshInProgress = true
      peripheral.setNotifyValue(false, for: buttonCharacteristic)
      scheduleMainNotificationRefreshTimeout(peripheral)
    case .enable:
      guard let buttonCharacteristic else { return }
      notificationRefreshInProgress = true
      peripheral.setNotifyValue(true, for: buttonCharacteristic)
      scheduleMainNotificationRefreshTimeout(peripheral)
    case .complete:
      notificationRefreshTimeoutWorkItem?.cancel()
      notificationRefreshTimeoutWorkItem = nil
      notificationRefreshInProgress = false
      let shouldRefreshAgain = notificationValidationPending
      notificationValidationPending = false
      duplicatePacketFilter.resetWindow()
      phase = "connected"
      message = "BLE Control H20 đã kết nối; nút MAIN sẵn sàng."
      emitStatus()
      if shouldRefreshAgain {
        scheduleMainNotificationRefresh()
      }
    }
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
    notificationRefreshWorkItem?.cancel()
    notificationRefreshWorkItem = nil
    notificationRefreshTimeoutWorkItem?.cancel()
    notificationRefreshTimeoutWorkItem = nil
    notificationRefreshInProgress = false
    notificationValidationPending = false
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
    audioSessionCoordinator.onMainTurnEnded = nil
    audioSessionCoordinator.onAudioSessionReleased = nil
    audioSessionCoordinator.onSpeechCaptureEnded = nil
    deferredReconnectPeripheral = nil
    notificationRefreshWorkItem?.cancel()
    notificationRefreshWorkItem = nil
    notificationRefreshTimeoutWorkItem?.cancel()
    notificationRefreshTimeoutWorkItem = nil
    notificationRefreshInProgress = false
    notificationValidationPending = false
    scanTimeoutWorkItem?.cancel()
    connectTimeoutWorkItem?.cancel()
    cancelReconnectTasks()
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
    reconnectTimeoutWorkItem?.cancel()
    reconnectTimeoutWorkItem = nil
    phase = "error"
    message = "Không kết nối được H20: \(error?.localizedDescription ?? "không rõ lỗi")"
    emitStatus()
    failPendingConnect(code: "CONNECT_FAILED", message: message!)
    let nsError = error as NSError?
    audioSessionCoordinator.trace(
      stage: "ble_connect_failed",
      caller: "Aiv0BleControlBridge.didFailToConnect",
      code: nsError.map { "\($0.domain):\($0.code)" },
      message: error?.localizedDescription ?? "unknown"
    )
    scheduleReconnect(peripheral)
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    let nsError = error as NSError?
    audioSessionCoordinator.trace(
      stage: "didDisconnectPeripheral",
      caller: "Aiv0BleControlBridge",
      code: nsError.map { "\($0.domain):\($0.code)" },
      message: error?.localizedDescription ?? "no CoreBluetooth error"
    )
    resetCharacteristics()
    reconnectTimeoutWorkItem?.cancel()
    reconnectTimeoutWorkItem = nil
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
    if notificationRefreshInProgress {
      notificationRefreshTimeoutWorkItem?.cancel()
      notificationRefreshTimeoutWorkItem = nil
      if let error {
        let nsError = error as NSError
        notificationRefreshInProgress = false
        audioSessionCoordinator.trace(
          stage: "ble_main_notification_refresh_failed",
          caller: "Aiv0BleControlBridge",
          code: "\(nsError.domain):\(nsError.code)",
          message: error.localizedDescription
        )
        if shouldDeferNotificationMaintenance() {
          notificationValidationPending = true
          return
        }
        central?.cancelPeripheralConnection(peripheral)
        return
      }
      refreshMainNotificationSubscription()
      return
    }
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
      if !duplicate,
        bytes.count == 12,
        bytes[0] == 0x01,
        bytes[1] == 0x01,
        bytes[3] == 0x01
      {
        audioSessionCoordinator.notePhysicalMain(rawHex: rawHex)
      }
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
