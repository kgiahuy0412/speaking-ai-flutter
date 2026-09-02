import AVFoundation
import CoreBluetooth
import Flutter
import Foundation
import MediaPlayer
import UIKit

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
  // Match Android's recovery budget. H20 can briefly drop its BLE GATT link
  // while iOS brings up the two-way HFP route, but MAIN must recover without
  // waiting for the user to open Parent settings.
  static let maxAttempts = 5

  static func delaySeconds(forAttempt attempt: Int) -> TimeInterval {
    switch max(attempt, 1) {
    case 1:
      // The disconnect callback is already definitive. An extra one-second
      // delay creates a window where a physical MAIN press is irretrievably
      // lost, so start the first CoreBluetooth reconnect immediately.
      return 0
    case 2:
      return 0.25
    default:
      return min(0.75 * pow(2.0, Double(attempt - 3)), 3.0)
    }
  }

  static func shouldDeferReconnect(
    mainTurnActive: Bool,
    promptActive: Bool,
    speechCaptureActive: Bool,
    hfpRouteActive: Bool
  ) -> Bool {
    // BLE GATT carries only H20 control packets. Reconnecting this link must
    // stay independent from the HFP audio route so a later MAIN press remains
    // available while a lesson prompt or speech capture is active.
    false
  }

  static func shouldDeferNotificationMaintenance(
    mainTurnActive: Bool,
    speechCaptureActive: Bool,
    hfpRouteActive: Bool
  ) -> Bool {
    // Re-arming the MAIN characteristic does not reconfigure AVAudioSession.
    // Deferring it for HFP/speech leaves the physical button unreachable.
    false
  }
}

/// Decides whether an iOS headset/remote-control event can safely stand in for
/// a missing BLE MAIN notification. H20 firmware 1.0.0 can temporarily drop
/// GATT while its HFP microphone is active, so this fallback is deliberately
/// limited to a foreground H20 capture or an explicitly-owned HFP session.
struct H20RemoteMainPolicy {
  static func shouldHandle(
    applicationIsActive: Bool,
    speechCaptureActive: Bool,
    hfpRouteActive: Bool,
    hfpPortNames: [String]
  ) -> Bool {
    applicationIsActive
      && (speechCaptureActive || hfpRouteActive)
      && hfpPortNames.contains { $0.localizedCaseInsensitiveContains("H20") }
  }

  /// Build an observed H20-shaped packet so the existing decoder, coordinator,
  /// and duplicate filter remain the single MAIN path for BLE and HFP remote
  /// events. Sequence and uptime are diagnostic transport fields only.
  static func syntheticPacket(
    sequence: UInt8,
    batteryPercent: Int?,
    uptimeMilliseconds: UInt32
  ) -> [UInt8] {
    let battery = UInt16(clamping: batteryPercent ?? 0)
    return [
      0x01, 0x01, sequence, 0x01,
      0xFF, 0xFF,
      UInt8(truncatingIfNeeded: battery),
      UInt8(truncatingIfNeeded: battery >> 8),
      UInt8(truncatingIfNeeded: uptimeMilliseconds),
      UInt8(truncatingIfNeeded: uptimeMilliseconds >> 8),
      UInt8(truncatingIfNeeded: uptimeMilliseconds >> 16),
      UInt8(truncatingIfNeeded: uptimeMilliseconds >> 24),
    ]
  }
}

/// Diagnostic coverage for every MediaPlayer command that a one-button HFP
/// accessory can plausibly emit. Once a physical H20 build identifies the
/// actual command, the production registration can be narrowed to that command.
struct H20RemoteMainDiagnosticPolicy {
  static let commandNames = [
    "togglePlayPause",
    "play",
    "pause",
    "stop",
    "nextTrack",
    "previousTrack",
    "seekForward",
    "seekBackward",
    "skipForward",
    "skipBackward",
    "changePlaybackRate",
    "changePlaybackPosition",
    "changeRepeatMode",
    "changeShuffleMode",
    "like",
    "dislike",
    "bookmark",
    "rating",
    "enableLanguageOption",
    "disableLanguageOption",
  ]

  static func registrations(
    commandCenter: MPRemoteCommandCenter
  ) -> [(name: String, command: MPRemoteCommand)] {
    let commands: [MPRemoteCommand] = [
      commandCenter.togglePlayPauseCommand,
      commandCenter.playCommand,
      commandCenter.pauseCommand,
      commandCenter.stopCommand,
      commandCenter.nextTrackCommand,
      commandCenter.previousTrackCommand,
      commandCenter.seekForwardCommand,
      commandCenter.seekBackwardCommand,
      commandCenter.skipForwardCommand,
      commandCenter.skipBackwardCommand,
      commandCenter.changePlaybackRateCommand,
      commandCenter.changePlaybackPositionCommand,
      commandCenter.changeRepeatModeCommand,
      commandCenter.changeShuffleModeCommand,
      commandCenter.likeCommand,
      commandCenter.dislikeCommand,
      commandCenter.bookmarkCommand,
      commandCenter.ratingCommand,
      commandCenter.enableLanguageOptionCommand,
      commandCenter.disableLanguageOptionCommand,
    ]
    precondition(commandNames.count == commands.count)
    return zip(commandNames, commands).map { (name: $0.0, command: $0.1) }
  }
}

/// MPRemoteCommandCenter only routes accessory events to a Now Playing app.
/// Speech capture has no audible output after the ready cue, so keep a real,
/// silent AVAudioPlayer running while H20 HFP owns the two-way audio route.
/// This is deliberately scoped to the diagnostic MAIN window and never changes
/// AVAudioSession category, mode, preferred input, or the Flutter lesson flow.
final class H20RemoteNowPlayingAnchor {
  enum AnchorError: LocalizedError {
    case playbackFailed

    var errorDescription: String? {
      "Không thể bắt đầu phiên Now Playing chẩn đoán MAIN H20."
    }
  }

  private var player: AVAudioPlayer?
  private var previousNowPlayingInfo: [String: Any]?
  private(set) var isActive = false

  @discardableResult
  func start() throws -> Bool {
    guard !isActive else { return false }

    let candidate = try AVAudioPlayer(data: Self.silentWaveData)
    candidate.numberOfLoops = -1
    candidate.volume = 0
    candidate.prepareToPlay()
    guard candidate.play() else {
      throw AnchorError.playbackFailed
    }

    let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    previousNowPlayingInfo = nowPlayingCenter.nowPlayingInfo
    nowPlayingCenter.nowPlayingInfo = [
      MPMediaItemPropertyTitle: "HOMI",
      MPMediaItemPropertyArtist: "MAIN H20 đang lắng nghe",
      MPNowPlayingInfoPropertyIsLiveStream: true,
      MPNowPlayingInfoPropertyPlaybackRate: 1.0,
    ]
    player = candidate
    isActive = true
    return true
  }

  @discardableResult
  func stop() -> Bool {
    guard isActive else { return false }
    player?.stop()
    player = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = previousNowPlayingInfo
    previousNowPlayingInfo = nil
    isActive = false
    return true
  }

  /// A valid 500 ms, mono, 16-bit PCM WAV containing digital silence. The
  /// player loops it only to establish active-playback ownership; it adds no
  /// audible cue and shares the already-active HFP route.
  static let silentWaveData: Data = {
    let sampleRate: UInt32 = 16_000
    let sampleCount: UInt32 = sampleRate / 2
    let channelCount: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let bytesPerSample = UInt32(bitsPerSample / 8)
    let dataSize = sampleCount * UInt32(channelCount) * bytesPerSample

    var data = Data("RIFF".utf8)
    appendLittleEndian(36 + dataSize, to: &data)
    data.append(Data("WAVEfmt ".utf8))
    appendLittleEndian(UInt32(16), to: &data)
    appendLittleEndian(UInt16(1), to: &data)
    appendLittleEndian(channelCount, to: &data)
    appendLittleEndian(sampleRate, to: &data)
    appendLittleEndian(sampleRate * UInt32(channelCount) * bytesPerSample, to: &data)
    appendLittleEndian(channelCount * UInt16(bytesPerSample), to: &data)
    appendLittleEndian(bitsPerSample, to: &data)
    data.append(Data("data".utf8))
    appendLittleEndian(dataSize, to: &data)
    data.append(Data(count: Int(dataSize)))
    return data
  }()

  private static func appendLittleEndian<T: FixedWidthInteger>(
    _ value: T,
    to data: inout Data
  ) {
    var littleEndianValue = value.littleEndian
    withUnsafeBytes(of: &littleEndianValue) { bytes in
      data.append(contentsOf: bytes)
    }
  }
}

enum Aiv0DisconnectRecoveryStep: Equatable {
  case ignore
  case waitForSystem
  case scheduleManualReconnect
}

struct Aiv0DisconnectRecoveryPolicy {
  static func nextStep(
    manualDisconnect: Bool,
    disposed: Bool,
    systemIsReconnecting: Bool
  ) -> Aiv0DisconnectRecoveryStep {
    if manualDisconnect || disposed { return .ignore }
    return systemIsReconnecting ? .waitForSystem : .scheduleManualReconnect
  }
}

enum Aiv0MainNotificationRefreshStep: Equatable {
  case reconnect
  case rediscover
  case enable
  case complete
}

/// Keep the H20 CCCD subscription stable across HFP/SCO activity. This mirrors
/// Android: a healthy notification is preserved and only a missing one is
/// enabled again after CoreBluetooth reports an actual link problem.
struct Aiv0MainNotificationRefreshPolicy {
  static func nextStep(
    peripheralConnected: Bool,
    hasButtonCharacteristic: Bool,
    refreshInProgress: Bool = false,
    isNotifying: Bool
  ) -> Aiv0MainNotificationRefreshStep {
    guard peripheralConnected else { return .reconnect }
    guard hasButtonCharacteristic else { return .rediscover }
    return isNotifying ? .complete : .enable
  }
}

enum Aiv0MainNotificationTimeoutStep: Equatable {
  case complete
  case reportFailure
  case reconnect
}

struct Aiv0MainNotificationTimeoutPolicy {
  static func nextStep(
    peripheralConnected: Bool,
    isNotifying: Bool
  ) -> Aiv0MainNotificationTimeoutStep {
    guard peripheralConnected else { return .reconnect }
    return isNotifying ? .complete : .reportFailure
  }
}

enum Aiv0DeferredRecoveryStep: Equatable {
  case wait
  case reconnect
  case rediscover
  case rearmNotification
}

struct Aiv0DeferredRecoveryTraceState {
  private var lastStep: Aiv0DeferredRecoveryStep?
  private(set) var repeatCount = 0

  mutating func record(_ step: Aiv0DeferredRecoveryStep) -> Bool {
    if lastStep == step {
      repeatCount += 1
      return false
    }
    lastStep = step
    repeatCount = 1
    return true
  }

  mutating func reset() {
    lastStep = nil
    repeatCount = 0
  }
}

struct Aiv0DeferredRecoveryPolicy {
  static func nextStep(
    audioCritical: Bool,
    peripheralConnected: Bool,
    hasButtonCharacteristic: Bool
  ) -> Aiv0DeferredRecoveryStep {
    guard peripheralConnected else { return .reconnect }
    return hasButtonCharacteristic ? .rearmNotification : .rediscover
  }
}

enum Aiv0ConnectStartStep: Equatable {
  case connect
  case rediscover
  case enable
  case complete
}

/// CoreBluetooth may return an H20 peripheral whose GATT link is already
/// attached to this process. Calling `connect` again in that state is not an
/// idempotent operation: iOS is not required to emit another `didConnect`, so
/// the app's connect timeout can end up cancelling a healthy link.
struct Aiv0ConnectStartPolicy {
  static func nextStep(
    peripheralConnected: Bool,
    hasButtonCharacteristic: Bool,
    hasStateCharacteristic: Bool,
    isNotifying: Bool
  ) -> Aiv0ConnectStartStep {
    guard peripheralConnected else { return .connect }
    guard hasButtonCharacteristic, hasStateCharacteristic else { return .rediscover }
    return isNotifying ? .complete : .enable
  }
}

enum Aiv0InitialNotificationSetupStep: Equatable {
  case enable
  case complete
}

/// Rediscovery can return the existing characteristic with notification still
/// enabled. In that case `setNotifyValue(true)` may not produce a new delegate
/// callback, so connection verification must complete immediately.
struct Aiv0InitialNotificationSetupPolicy {
  static func nextStep(isNotifying: Bool) -> Aiv0InitialNotificationSetupStep {
    isNotifying ? .complete : .enable
  }
}

/// iOS implementation of the same AIV0/H20 BLE control contract used by the
/// Android bridge. Audio remains on HFP; BLE normally carries MAIN button
/// notifications, battery/firmware diagnostics, and optional APP State. A
/// narrowly-scoped iOS headset fallback covers MAIN while H20 GATT is absent.
final class Aiv0BleControlBridge: NSObject, FlutterStreamHandler {
  private struct RemoteCommandRegistration {
    let command: MPRemoteCommand
    let target: Any
  }

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
  private var deferredRecoveryWorkItem: DispatchWorkItem?
  private var notificationRefreshWorkItem: DispatchWorkItem?
  private var notificationRefreshTimeoutWorkItem: DispatchWorkItem?
  private weak var deferredReconnectPeripheral: CBPeripheral?
  private var notificationRefreshInProgress = false
  private var notificationValidationPending = false
  private var deferredRecoveryTraceState = Aiv0DeferredRecoveryTraceState()
  private var phase = "idle"
  private var message: String?
  private var writeMode: String?
  private var batteryPercent: Int?
  private var firmwareRevision: String?
  private var lastRawHex: String?
  private var lastMainTransportSource: String?
  private var duplicatePacketFilter = Aiv0DuplicatePacketFilter()
  private var packetCount = 0
  private var invalidPacketCount = 0
  private var remoteMainCount = 0
  private var remoteMainDuplicateCount = 0
  private var remoteMainSequence: UInt8 = 0
  private var remoteMainCommandsEnabled = false
  private var remoteCommandRegistrations: [RemoteCommandRegistration] = []
  private let remoteNowPlayingAnchor = H20RemoteNowPlayingAnchor()
  private var lastRemoteCommandName: String?
  private var transportBridgingRequestCount = 0
  private var reconnectAttempt = 0
  private var reconnectCount = 0
  private var lastDisconnectEpochMs: Int?
  private var lastDisconnectCode: String?
  private var lastDisconnectMessage: String?
  private var lastDisconnectPeripheralState: String?
  private var lastNotificationRecovery: String?
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
    registerRemoteMainCommands()
    audioSessionCoordinator.onMainTurnEnded = { [weak self] in
      // Match Android: HFP activity never tears down a healthy BLE
      // subscription. Resume only work created by a real BLE failure.
      self?.resumeDeferredBluetoothRecovery()
    }
    audioSessionCoordinator.onSpeechCaptureStarted = { [weak self] in
      self?.updateRemoteMainCommandAvailability(reason: "speech_capture_started")
    }
    audioSessionCoordinator.onSpeechCaptureEnded = { [weak self] in
      self?.updateRemoteMainCommandAvailability(reason: "speech_capture_ended")
      // A capture ending is not evidence that CoreBluetooth lost MAIN notify.
      // Resume only work that an actual BLE failure deferred during capture.
      self?.resumeDeferredBluetoothRecovery()
    }
    audioSessionCoordinator.onHfpRouteOwnershipChanged = { [weak self] in
      self?.updateRemoteMainCommandAvailability(reason: "hfp_route_ownership_changed")
    }
    audioSessionCoordinator.onPromptEnded = { [weak self] in
      // Prompt playback and speech capture are equally unsafe windows for a
      // CoreBluetooth reconnect on H20. Resume the exact deferred operation
      // only after the prompt owner has released the shared audio session.
      self?.resumeDeferredBluetoothRecovery()
    }
    audioSessionCoordinator.onAudioSessionReleased = { [weak self] in
      self?.updateRemoteMainCommandAvailability(reason: "audio_session_released")
      self?.resumeDeferredBluetoothRecovery()
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
    case "markParentDiagnosticsOpened":
      audioSessionCoordinator.trace(
        stage: "PARENT_SCREEN_OPENED",
        caller: "Aiv0BleControlBridge.methodChannel",
        values: [
          "phase": phase,
          "peripheralState": connectedPeripheral.map { String(describing: $0.state) } ?? "unavailable",
          "mainNotificationState": buttonCharacteristic?.isNotifying == true ? "notifying" : "unavailable",
        ]
      )
      emitStatus()
      result(snapshot())
    case "recordMainDiagnostic":
      let arguments = call.arguments as? [String: Any]
      let requestedStage = (arguments?["stage"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard requestedStage.hasPrefix("MAIN_") else {
        result(
          FlutterError(
            code: "INVALID_DIAGNOSTIC_STAGE",
            message: "MAIN diagnostic stage is invalid.",
            details: nil
          )
        )
        return
      }
      var values = arguments?["values"] as? [String: Any] ?? [:]
      if let dartEventEpochMs = arguments?["dartEventEpochMs"] as? NSNumber {
        values["dartEventEpochMs"] = dartEventEpochMs.intValue
      }
      audioSessionCoordinator.trace(
        stage: requestedStage,
        caller: "Flutter.MainDispatch",
        message: arguments?["message"] as? String,
        values: values
      )
      result(nil)
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
    let reusesCurrentPeripheral = connectedPeripheral?.identifier == peripheral.identifier
    let startStep = Aiv0ConnectStartPolicy.nextStep(
      peripheralConnected: peripheral.state == .connected,
      hasButtonCharacteristic: reusesCurrentPeripheral && buttonCharacteristic != nil,
      hasStateCharacteristic: reusesCurrentPeripheral && stateCharacteristic != nil,
      isNotifying: reusesCurrentPeripheral && (buttonCharacteristic?.isNotifying ?? false)
    )
    cancelReconnectTasks()
    reconnectAttempt = 0
    manualDisconnect = false
    connectedPeripheral = peripheral
    peripheral.delegate = self
    pendingConnectResult = result
    phase = "connecting"
    message = startStep == .complete
      ? "BLE Control H20 đã kết nối; nút MAIN sẵn sàng."
      : "Đang kết nối BLE Control H20…"
    emitStatus()
    audioSessionCoordinator.trace(
      stage: "ble_connect_start",
      caller: "Aiv0BleControlBridge.connect",
      message: String(describing: startStep)
    )
    if startStep == .connect, shouldDeferBluetoothReconnect() {
      deferredReconnectPeripheral = peripheral
      phase = "reconnecting"
      message = "BLE H20 đang chờ câu dẫn/ghi âm kết thúc; HFP không bị thay đổi."
      audioSessionCoordinator.trace(
        stage: "ble_connect_deferred_for_audio",
        caller: "Aiv0BleControlBridge.connect"
      )
      emitStatus()
      return
    }
    switch startStep {
    case .complete:
      completeConnection()
    case .enable:
      guard let buttonCharacteristic else {
        resetCharacteristics()
        peripheral.discoverServices([
          ProtocolUUID.controlService,
          ProtocolUUID.batteryService,
          ProtocolUUID.deviceInformationService,
        ])
        scheduleConnectTimeout()
        return
      }
      peripheral.setNotifyValue(true, for: buttonCharacteristic)
      scheduleConnectTimeout()
    case .rediscover:
      resetCharacteristics()
      peripheral.discoverServices([
        ProtocolUUID.controlService,
        ProtocolUUID.batteryService,
        ProtocolUUID.deviceInformationService,
      ])
      scheduleConnectTimeout()
    case .connect:
      resetCharacteristics()
      connectPeripheral(peripheral, using: manager)
      scheduleConnectTimeout()
    }
  }

  private func disconnect(_ result: @escaping FlutterResult) {
    manualDisconnect = true
    cancelReconnectTasks()
    connectTimeoutWorkItem?.cancel()
    connectTimeoutWorkItem = nil
    failPendingConnect(code: "CONNECT_CANCELLED", message: "Đã hủy kết nối H20.")
    if let peripheral = connectedPeripheral {
      requestPeripheralDisconnect(
        peripheral,
        caller: "Aiv0BleControlBridge.disconnect",
        code: "manual_disconnect"
      )
    }
    resetCharacteristics()
    connectedPeripheral = nil
    phase = "idle"
    message = nil
    emitStatus()
    result(nil)
  }

  private func requestPeripheralDisconnect(
    _ peripheral: CBPeripheral,
    caller: String,
    code: String
  ) {
    audioSessionCoordinator.trace(
      stage: "BLE_DISCONNECT_REQUESTED",
      caller: caller,
      code: code,
      values: ["peripheralState": String(describing: peripheral.state)]
    )
    central?.cancelPeripheralConnection(peripheral)
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
        self.requestPeripheralDisconnect(
          peripheral,
          caller: "Aiv0BleControlBridge.connectTimeout",
          code: "connect_timeout"
        )
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
    reconnectAttempt = 0
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

  private func connectPeripheral(_ peripheral: CBPeripheral, using manager: CBCentralManager) {
    var options: [String: Any] = [
      CBConnectPeripheralOptionEnableTransportBridgingKey: true,
    ]
    var autoReconnectEnabled = false
    if #available(iOS 17.0, *) {
      // H20 can drop BLE GATT while Classic Bluetooth HFP renegotiates. Keep
      // recovery owned by CoreBluetooth instead of a Flutter screen lifecycle.
      options[CBConnectPeripheralOptionEnableAutoReconnect] = true
      autoReconnectEnabled = true
    }
    transportBridgingRequestCount += 1
    audioSessionCoordinator.trace(
      stage: "BLE_CONNECT_OPTIONS",
      caller: "Aiv0BleControlBridge.connectPeripheral",
      values: [
        "autoReconnect": autoReconnectEnabled,
        "deviceId": peripheral.identifier.uuidString,
        "transportBridging": true,
      ]
    )
    manager.connect(peripheral, options: options)
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
    // A connected CBPeripheral must never be passed to central.connect again.
    // HFP can leave the GATT link attached while only MAIN notification
    // delivery is stale; recover the CCCD on that existing link instead.
    if peripheral.state == .connected {
      deferredReconnectPeripheral = peripheral
      resumeDeferredBluetoothRecovery()
      return
    }
    guard reconnectWorkItem == nil else {
      return
    }
    guard !manualDisconnect, !disposed,
      reconnectAttempt < Aiv0ReconnectPolicy.maxAttempts
    else {
      phase = "error"
      message = "Kết nối BLE Control H20 đã mất."
      emitStatus()
      failPendingConnect(code: "RECONNECT_EXHAUSTED", message: message!)
      return
    }
    reconnectAttempt += 1
    reconnectCount += 1
    let attempt = reconnectAttempt
    phase = "reconnecting"
    message = "Đang kết nối lại H20 (lần \(attempt)/\(Aiv0ReconnectPolicy.maxAttempts))…"
    emitStatus()
    let delay = Aiv0ReconnectPolicy.delaySeconds(forAttempt: attempt)
    audioSessionCoordinator.trace(
      stage: "ble_manual_reconnect_scheduled",
      caller: "Aiv0BleControlBridge.scheduleReconnect",
      values: [
        "attempt": attempt,
        "delayMs": Int(delay * 1_000),
        "hfpRouteActive": audioSessionCoordinator.hasTwoWayHfpRoute(),
        "speechCaptureActive": audioSessionCoordinator.isSpeechCaptureActive,
      ]
    )
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
      if peripheral.state == .connected {
        self.deferredReconnectPeripheral = peripheral
        self.resumeDeferredBluetoothRecovery()
        return
      }
      self.resetCharacteristics()
      peripheral.delegate = self
      if let manager = self.central {
        self.audioSessionCoordinator.trace(
          stage: "ble_manual_reconnect_started",
          caller: "Aiv0BleControlBridge.reconnectWorkItem",
          values: [
            "attempt": attempt,
            "hfpRouteActive": self.audioSessionCoordinator.hasTwoWayHfpRoute(),
            "speechCaptureActive": self.audioSessionCoordinator.isSpeechCaptureActive,
          ]
        )
        self.connectPeripheral(peripheral, using: manager)
      }
      // CoreBluetooth connection requests intentionally have no application
      // timeout. On iOS 15–16 this pending request is the fallback that keeps
      // waiting for H20 instead of giving up until Parent settings is opened.
    }
    reconnectWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
  }

  private func cancelReconnectTasks() {
    reconnectWorkItem?.cancel()
    reconnectWorkItem = nil
    deferredRecoveryWorkItem?.cancel()
    deferredRecoveryWorkItem = nil
    deferredReconnectPeripheral = nil
    deferredRecoveryTraceState.reset()
  }

  private func shouldDeferBluetoothReconnect() -> Bool {
    Aiv0ReconnectPolicy.shouldDeferReconnect(
      mainTurnActive: audioSessionCoordinator.isMainTurnActive,
      promptActive: audioSessionCoordinator.isPromptActive,
      speechCaptureActive: audioSessionCoordinator.isSpeechCaptureActive,
      hfpRouteActive: audioSessionCoordinator.hasTwoWayHfpRoute()
    )
  }

  private func shouldDeferNotificationMaintenance() -> Bool {
    Aiv0ReconnectPolicy.shouldDeferNotificationMaintenance(
      mainTurnActive: audioSessionCoordinator.isMainTurnActive,
      speechCaptureActive: audioSessionCoordinator.isSpeechCaptureActive,
      hfpRouteActive: audioSessionCoordinator.hasTwoWayHfpRoute()
    )
  }

  private func shouldDeferForcedNotificationRecovery() -> Bool {
    // CoreBluetooth notification recovery is intentionally isolated from the
    // HFP mic/speaker lifecycle. It must be allowed during an active lesson.
    false
  }

  private func scheduleDeferredBluetoothRecoveryRetry() {
    guard deferredRecoveryWorkItem == nil, !disposed else { return }
    let item = DispatchWorkItem { [weak self] in
      guard let self, !self.disposed else { return }
      self.deferredRecoveryWorkItem = nil
      self.resumeDeferredBluetoothRecovery()
    }
    deferredRecoveryWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
  }

  private func resumeDeferredBluetoothRecovery() {
    guard !disposed else { return }
    if let peripheral = deferredReconnectPeripheral {
      let connected = peripheral.state == .connected
      let step = Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: connected
          ? shouldDeferForcedNotificationRecovery()
          : shouldDeferBluetoothReconnect(),
        peripheralConnected: connected,
        hasButtonCharacteristic: buttonCharacteristic != nil
      )
      let changedStep = deferredRecoveryTraceState.record(step)
      let repeatCount = deferredRecoveryTraceState.repeatCount
      let shouldReport = changedStep || repeatCount == 4 || repeatCount % 20 == 0
      if shouldReport {
        audioSessionCoordinator.trace(
          stage: "ble_deferred_recovery",
          caller: "Aiv0BleControlBridge",
          message: String(describing: step),
          values: [
            "peripheralState": String(describing: peripheral.state),
            "repeatCount": repeatCount,
          ]
        )
        emitStatus()
      }
      switch step {
      case .wait:
        scheduleDeferredBluetoothRecoveryRetry()
        return
      case .reconnect:
        deferredReconnectPeripheral = nil
        scheduleReconnect(peripheral)
        return
      case .rediscover:
        deferredReconnectPeripheral = nil
        peripheral.delegate = self
        phase = "connecting"
        message = "Đang khôi phục nút MAIN H20…"
        emitStatus()
        peripheral.discoverServices([
          ProtocolUUID.controlService,
          ProtocolUUID.batteryService,
          ProtocolUUID.deviceInformationService,
        ])
        return
      case .rearmNotification:
        deferredReconnectPeripheral = nil
        notificationValidationPending = true
      }
    }
    if notificationValidationPending {
      notificationValidationPending = false
      scheduleMainNotificationRefresh()
    }
  }

  private func scheduleMainNotificationRefresh() {
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
      if self.notificationRefreshInProgress {
        self.notificationValidationPending = true
        return
      }
      self.notificationValidationPending = false
      self.refreshMainNotificationSubscription()
    }
    notificationRefreshWorkItem = item
    // Coalesce repeated CoreBluetooth recovery callbacks. This delay is not
    // coupled to AVAudioSession and never toggles a healthy subscription.
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
      let step = Aiv0MainNotificationTimeoutPolicy.nextStep(
        peripheralConnected: peripheral.state == .connected,
        isNotifying: self.buttonCharacteristic?.isNotifying ?? false
      )
      self.audioSessionCoordinator.trace(
        stage: "ble_main_notification_refresh_timeout",
        caller: "Aiv0BleControlBridge",
        message: String(describing: step)
      )
      switch step {
      case .complete:
        self.refreshMainNotificationSubscription()
      case .reportFailure:
        self.phase = "error"
        self.message = "BLE H20 vẫn kết nối nhưng chưa xác nhận MAIN Notify."
        self.lastNotificationRecovery = "timeout • connected • notify=disabled"
        self.emitStatus()
        self.failPendingConnect(code: "NOTIFY_TIMEOUT", message: self.message!)
      case .reconnect:
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
    let peripheralState = String(describing: peripheral.state)
    let notificationState = buttonCharacteristic == nil
      ? "unavailable"
      : (buttonCharacteristic?.isNotifying == true ? "notifying" : "disabled")
    lastNotificationRecovery = "\(step) • peripheral=\(peripheralState) • notify=\(notificationState)"
    audioSessionCoordinator.trace(
      stage: "ble_main_notification_refresh",
      caller: "Aiv0BleControlBridge",
      message: String(describing: step),
      values: [
        "peripheralState": peripheralState,
        "notificationState": notificationState,
      ]
    )
    emitStatus()
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
    case .enable:
      guard let buttonCharacteristic else { return }
      notificationRefreshInProgress = true
      peripheral.setNotifyValue(true, for: buttonCharacteristic)
      scheduleMainNotificationRefreshTimeout(peripheral)
    case .complete:
      notificationRefreshTimeoutWorkItem?.cancel()
      notificationRefreshTimeoutWorkItem = nil
      notificationRefreshInProgress = false
      deferredRecoveryTraceState.reset()
      let shouldRefreshAgain = notificationValidationPending
      notificationValidationPending = false
      duplicatePacketFilter.resetWindow()
      phase = "connected"
      message = "BLE Control H20 đã kết nối; nút MAIN sẵn sàng."
      lastNotificationRecovery = "complete • peripheral=\(peripheralState) • notify=\(notificationState)"
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
      if let peripheral = connectedPeripheral {
        requestPeripheralDisconnect(
          peripheral,
          caller: "Aiv0BleControlBridge.validateControlCharacteristics",
          code: "protocol_mismatch"
        )
      }
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
    switch Aiv0InitialNotificationSetupPolicy.nextStep(isNotifying: button.isNotifying) {
    case .complete:
      audioSessionCoordinator.trace(
        stage: "ble_notification_already_active",
        caller: "Aiv0BleControlBridge.validateControlCharacteristics"
      )
      audioSessionCoordinator.trace(
        stage: "MAIN_NOTIFY_ENABLED",
        caller: "Aiv0BleControlBridge.validateControlCharacteristics",
        values: [
          "peripheralState": connectedPeripheral.map { String(describing: $0.state) } ?? "unavailable"
        ]
      )
      completeConnection()
    case .enable:
      connectedPeripheral?.setNotifyValue(true, for: button)
    }
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
    deferredRecoveryTraceState.reset()
  }

  private func finishScanIfNeeded() {
    guard pendingScanResult != nil else { return }
    finishScan()
  }

  private func registerRemoteMainCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.skipForwardCommand.preferredIntervals = [15]
    commandCenter.skipBackwardCommand.preferredIntervals = [15]
    commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [1]
    commandCenter.ratingCommand.minimumRating = 0
    commandCenter.ratingCommand.maximumRating = 5
    let commands = H20RemoteMainDiagnosticPolicy.registrations(
      commandCenter: commandCenter
    )
    for (name, command) in commands {
      command.isEnabled = false
      let target = command.addTarget { [weak self] event -> MPRemoteCommandHandlerStatus in
        return self?.handleRemoteMainCommand(name: name, event: event) ?? .commandFailed
      }
      remoteCommandRegistrations.append(
        RemoteCommandRegistration(command: command, target: target)
      )
    }
  }

  private func unregisterRemoteMainCommands() {
    if remoteMainCommandsEnabled {
      UIApplication.shared.endReceivingRemoteControlEvents()
    }
    for registration in remoteCommandRegistrations {
      registration.command.isEnabled = false
      registration.command.removeTarget(registration.target)
    }
    remoteCommandRegistrations.removeAll()
    remoteMainCommandsEnabled = false
    remoteNowPlayingAnchor.stop()
  }

  private func updateRemoteMainCommandAvailability(reason: String) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.updateRemoteMainCommandAvailability(reason: reason)
      }
      return
    }
    let hfpPortNames = audioSessionCoordinator.session.currentRoute.inputs
      .filter { $0.portType == .bluetoothHFP }
      .map(\.portName)
    let shouldEnable = H20RemoteMainPolicy.shouldHandle(
      applicationIsActive: UIApplication.shared.applicationState == .active,
      speechCaptureActive: audioSessionCoordinator.isSpeechCaptureActive,
      hfpRouteActive: audioSessionCoordinator.isHfpRouteActive,
      hfpPortNames: hfpPortNames
    )
    setRemoteMainCommandsEnabled(shouldEnable, reason: reason)
  }

  private func setRemoteMainCommandsEnabled(_ enabled: Bool, reason: String) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.setRemoteMainCommandsEnabled(enabled, reason: reason)
      }
      return
    }
    guard remoteMainCommandsEnabled != enabled else { return }
    remoteMainCommandsEnabled = enabled
    for registration in remoteCommandRegistrations {
      registration.command.isEnabled = enabled
    }
    if enabled {
      do {
        if try remoteNowPlayingAnchor.start() {
          audioSessionCoordinator.trace(
            stage: "MAIN_REMOTE_NOW_PLAYING_STARTED",
            caller: "H20RemoteMainBridge",
            message: reason,
            values: ["silentAnchorPlaying": true]
          )
        }
      } catch {
        audioSessionCoordinator.trace(
          stage: "MAIN_REMOTE_NOW_PLAYING_FAILED",
          caller: "H20RemoteMainBridge",
          code: "NOW_PLAYING_START_FAILED",
          message: error.localizedDescription
        )
      }
      UIApplication.shared.beginReceivingRemoteControlEvents()
    } else {
      UIApplication.shared.endReceivingRemoteControlEvents()
      if remoteNowPlayingAnchor.stop() {
        audioSessionCoordinator.trace(
          stage: "MAIN_REMOTE_NOW_PLAYING_STOPPED",
          caller: "H20RemoteMainBridge",
          message: reason
        )
      }
    }
    audioSessionCoordinator.trace(
      stage: enabled ? "MAIN_REMOTE_LISTENING_ENABLED" : "MAIN_REMOTE_LISTENING_DISABLED",
      caller: "H20RemoteMainBridge",
      message: reason,
      values: [
        "speechCaptureActive": audioSessionCoordinator.isSpeechCaptureActive,
        "hfpRouteActive": audioSessionCoordinator.isHfpRouteActive,
        "nowPlayingAnchorActive": remoteNowPlayingAnchor.isActive,
        "registeredCommandCount": remoteCommandRegistrations.count,
        "route": audioSessionCoordinator.routeDescription(),
      ]
    )
    emitStatus()
  }

  private func handleRemoteMainCommand(
    name: String,
    event: MPRemoteCommandEvent
  ) -> MPRemoteCommandHandlerStatus {
    if Thread.isMainThread {
      return deliverRemoteMainCommand(name: name, event: event) ? .success : .commandFailed
    }
    var delivered = false
    DispatchQueue.main.sync {
      delivered = deliverRemoteMainCommand(name: name, event: event)
    }
    return delivered ? .success : .commandFailed
  }

  private func deliverRemoteMainCommand(
    name: String,
    event: MPRemoteCommandEvent
  ) -> Bool {
    guard !disposed else { return false }
    lastRemoteCommandName = name
    let hfpPortNames = audioSessionCoordinator.session.currentRoute.inputs
      .filter { $0.portType == .bluetoothHFP }
      .map(\.portName)
    let shouldHandle = H20RemoteMainPolicy.shouldHandle(
      applicationIsActive: UIApplication.shared.applicationState == .active,
      speechCaptureActive: audioSessionCoordinator.isSpeechCaptureActive,
      hfpRouteActive: audioSessionCoordinator.isHfpRouteActive,
      hfpPortNames: hfpPortNames
    )
    guard shouldHandle else {
      audioSessionCoordinator.trace(
        stage: "MAIN_REMOTE_IGNORED",
        caller: "H20RemoteMainBridge",
        message: name,
        values: [
          "applicationState": String(describing: UIApplication.shared.applicationState),
          "eventClass": String(describing: type(of: event)),
          "eventTimestamp": event.timestamp,
          "speechCaptureActive": audioSessionCoordinator.isSpeechCaptureActive,
          "hfpRouteActive": audioSessionCoordinator.isHfpRouteActive,
          "hfpPortNames": hfpPortNames,
        ]
      )
      emitStatus()
      return false
    }

    remoteMainSequence &+= 1
    let uptimeMilliseconds = UInt32(
      truncatingIfNeeded: Int64(ProcessInfo.processInfo.systemUptime * 1_000)
    )
    let bytes = H20RemoteMainPolicy.syntheticPacket(
      sequence: remoteMainSequence,
      batteryPercent: batteryPercent,
      uptimeMilliseconds: uptimeMilliseconds
    )
    let rawHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    let duplicate = duplicatePacketFilter.register(
      bytes: bytes,
      uptimeMilliseconds: ProcessInfo.processInfo.systemUptime * 1_000
    )
    remoteMainCount += 1
    if duplicate { remoteMainDuplicateCount += 1 }
    lastRawHex = rawHex
    lastMainTransportSource = "hfpRemote"

    var receivedValues = remoteCommandEventValues(event)
    receivedValues["duplicate"] = duplicate
    receivedValues["eventSinkAttached"] = eventSink != nil
    receivedValues["rawHex"] = rawHex
    receivedValues["route"] = audioSessionCoordinator.routeDescription()
    audioSessionCoordinator.trace(
      stage: "MAIN_REMOTE_RECEIVED",
      caller: "H20RemoteMainBridge",
      message: name,
      values: receivedValues
    )
    if !duplicate {
      audioSessionCoordinator.notePhysicalMain(rawHex: rawHex, source: "hfpRemote")
      audioSessionCoordinator.trace(
        stage: "MAIN_EVENT_DELIVERY_ATTEMPT",
        caller: "H20RemoteMainBridge.eventChannel",
        message: rawHex,
        values: [
          "eventSinkAttached": eventSink != nil,
          "sequence": Int(remoteMainSequence),
          "transportSource": "hfpRemote",
        ]
      )
    }
    eventSink?([
      "type": "button",
      "bytes": bytes.map { Int($0) },
      "deviceId": connectedPeripheral?.identifier.uuidString ?? "H20-HFP",
      "duplicate": duplicate,
      "remoteCommandName": name,
      "transportSource": "hfpRemote",
      "receivedAtEpochMs": Int(Date().timeIntervalSince1970 * 1_000),
    ])
    emitStatus()
    return eventSink != nil
  }

  private func remoteCommandEventValues(
    _ event: MPRemoteCommandEvent
  ) -> [String: Any] {
    var values: [String: Any] = [
      "eventClass": String(describing: type(of: event)),
      "eventTimestamp": event.timestamp,
    ]
    if let skipEvent = event as? MPSkipIntervalCommandEvent {
      values["interval"] = skipEvent.interval
    }
    if let seekEvent = event as? MPSeekCommandEvent {
      values["seekType"] = String(describing: seekEvent.type)
    }
    if let rateEvent = event as? MPChangePlaybackRateCommandEvent {
      values["playbackRate"] = rateEvent.playbackRate
    }
    if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
      values["positionTime"] = positionEvent.positionTime
    }
    if let ratingEvent = event as? MPRatingCommandEvent {
      values["rating"] = ratingEvent.rating
    }
    return values
  }

  private func snapshot() -> [String: Any] {
    var value: [String: Any] = [
      "type": "status",
      "phase": phase,
      "packetCount": packetCount,
      "invalidPacketCount": invalidPacketCount,
      "duplicatePacketCount": duplicatePacketFilter.duplicateCount,
      "remoteMainCount": remoteMainCount,
      "remoteMainDuplicateCount": remoteMainDuplicateCount,
      "remoteMainCommandsEnabled": remoteMainCommandsEnabled,
      "remoteNowPlayingAnchorActive": remoteNowPlayingAnchor.isActive,
      "remoteCommandRegistrationCount": remoteCommandRegistrations.count,
      "transportBridgingRequestCount": transportBridgingRequestCount,
      "reconnectCount": reconnectCount,
      "deferredRecoveryRepeatCount": deferredRecoveryTraceState.repeatCount,
      "diagnosticTimeline": audioSessionCoordinator.diagnosticTimelineSnapshot(limit: 80),
    ]
    if let peripheral = connectedPeripheral {
      value["deviceId"] = peripheral.identifier.uuidString
      value["deviceName"] = peripheral.name ?? discoveredDevices[peripheral.identifier]?.name ?? "H20"
      value["peripheralState"] = String(describing: peripheral.state)
    } else {
      value["peripheralState"] = "unavailable"
    }
    value["mainNotificationState"] = buttonCharacteristic == nil
      ? "unavailable"
      : (buttonCharacteristic?.isNotifying == true ? "notifying" : "disabled")
    if let message { value["message"] = message }
    if let writeMode { value["writeMode"] = writeMode }
    if let batteryPercent { value["batteryPercent"] = batteryPercent }
    if let firmwareRevision { value["firmwareRevision"] = firmwareRevision }
    if let lastRawHex { value["lastRawHex"] = lastRawHex }
    if let lastMainTransportSource { value["lastMainTransportSource"] = lastMainTransportSource }
    if let lastRemoteCommandName { value["lastRemoteCommandName"] = lastRemoteCommandName }
    if let lastDisconnectEpochMs { value["lastDisconnectEpochMs"] = lastDisconnectEpochMs }
    if let lastDisconnectCode { value["lastDisconnectCode"] = lastDisconnectCode }
    if let lastDisconnectMessage { value["lastDisconnectMessage"] = lastDisconnectMessage }
    if let lastDisconnectPeripheralState {
      value["lastDisconnectPeripheralState"] = lastDisconnectPeripheralState
    }
    if let lastNotificationRecovery {
      value["lastNotificationRecovery"] = lastNotificationRecovery
    }
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
    audioSessionCoordinator.onSpeechCaptureStarted = nil
    audioSessionCoordinator.onSpeechCaptureEnded = nil
    audioSessionCoordinator.onHfpRouteOwnershipChanged = nil
    audioSessionCoordinator.onPromptEnded = nil
    audioSessionCoordinator.onAudioSessionReleased = nil
    deferredReconnectPeripheral = nil
    deferredRecoveryWorkItem?.cancel()
    deferredRecoveryWorkItem = nil
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
    if let peripheral = connectedPeripheral {
      requestPeripheralDisconnect(
        peripheral,
        caller: "Aiv0BleControlBridge.dispose",
        code: "bridge_disposed"
      )
    }
    pendingPermissionResults.forEach { $0(false) }
    pendingPermissionResults.removeAll()
    pendingScanResult?(FlutterError(code: "BLE_DISPOSED", message: "Đã đóng cầu nối BLE.", details: nil))
    pendingScanResult = nil
    failPendingConnect(code: "BLE_DISPOSED", message: "Đã đóng cầu nối BLE.")
    pendingWriteResult?(FlutterError(code: "BLE_DISPOSED", message: "Đã đóng cầu nối BLE.", details: nil))
    pendingWriteResult = nil
    eventSink = nil
    unregisterRemoteMainCommands()
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
    lastNotificationRecovery = "connected • peripheral=\(peripheral.state) • notify=discovering"
    audioSessionCoordinator.trace(
      stage: "BLE_CONNECTED",
      caller: "Aiv0BleControlBridge.didConnect",
      values: [
        "deviceId": peripheral.identifier.uuidString,
        "peripheralState": String(describing: peripheral.state),
      ]
    )
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
    handleDisconnect(
      peripheral,
      error: error,
      systemIsReconnecting: false
    )
  }

  @available(iOS 15.0, *)
  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    timestamp: CFAbsoluteTime,
    isReconnecting: Bool,
    error: Error?
  ) {
    handleDisconnect(
      peripheral,
      error: error,
      systemIsReconnecting: isReconnecting
    )
  }

  private func handleDisconnect(
    _ peripheral: CBPeripheral,
    error: Error?,
    systemIsReconnecting: Bool
  ) {
    let nsError = error as NSError?
    let peripheralState = String(describing: peripheral.state)
    let disconnectCode = nsError.map { "\($0.domain):\($0.code)" } ?? "none"
    let disconnectMessage = error?.localizedDescription ?? "no CoreBluetooth error"
    lastDisconnectEpochMs = Int(Date().timeIntervalSince1970 * 1_000)
    lastDisconnectCode = disconnectCode
    lastDisconnectMessage = disconnectMessage
    lastDisconnectPeripheralState = peripheralState
    lastNotificationRecovery = "disconnect • peripheral=\(peripheralState) • systemReconnect=\(systemIsReconnecting) • notify=unavailable"
    if !manualDisconnect && !disposed {
      phase = "reconnecting"
      message = systemIsReconnecting
        ? "BLE GATT H20 vừa ngắt; iOS đang tự khôi phục MAIN."
        : "BLE GATT H20 vừa ngắt; đang chờ khôi phục MAIN."
    }
    audioSessionCoordinator.trace(
      stage: "BLE_DISCONNECTED",
      caller: "Aiv0BleControlBridge",
      code: disconnectCode,
      message: disconnectMessage,
      values: [
        "peripheralState": peripheralState,
        "systemIsReconnecting": systemIsReconnecting,
      ]
    )
    emitStatus()
    resetCharacteristics()
    let recoveryStep = Aiv0DisconnectRecoveryPolicy.nextStep(
      manualDisconnect: manualDisconnect,
      disposed: disposed,
      systemIsReconnecting: systemIsReconnecting
    )
    switch recoveryStep {
    case .ignore:
      phase = "idle"
      message = nil
      emitStatus()
    case .waitForSystem:
      // Do not race a second central.connect call against CoreBluetooth's
      // system-owned reconnect. didConnect will rediscover services and MAIN.
      cancelReconnectTasks()
      reconnectAttempt = 0
      reconnectCount += 1
      audioSessionCoordinator.trace(
        stage: "ble_system_auto_reconnect_waiting",
        caller: "Aiv0BleControlBridge"
      )
      emitStatus()
    case .scheduleManualReconnect:
      scheduleReconnect(peripheral)
    }
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
    let peripheralState = String(describing: peripheral.state)
    let notificationState = characteristic.isNotifying ? "notifying" : "disabled"
    if notificationRefreshInProgress {
      notificationRefreshTimeoutWorkItem?.cancel()
      notificationRefreshTimeoutWorkItem = nil
      if let error {
        let nsError = error as NSError
        notificationRefreshInProgress = false
        lastNotificationRecovery = "failed • peripheral=\(peripheralState) • notify=\(notificationState) • \(nsError.domain):\(nsError.code)"
        emitStatus()
        audioSessionCoordinator.trace(
          stage: "ble_main_notification_refresh_failed",
          caller: "Aiv0BleControlBridge",
          code: "\(nsError.domain):\(nsError.code)",
          message: error.localizedDescription
        )
        // A real CoreBluetooth notification error is the only maintenance
        // failure that may tear down the link and enter normal reconnect.
        requestPeripheralDisconnect(
          peripheral,
          caller: "Aiv0BleControlBridge.notificationRefresh",
          code: "notification_refresh_failed"
        )
        return
      }
      lastNotificationRecovery = "callback • peripheral=\(peripheralState) • notify=\(notificationState)"
      audioSessionCoordinator.trace(
        stage: "ble_main_notification_state_updated",
        caller: "Aiv0BleControlBridge",
        message: notificationState,
        values: [
          "peripheralState": peripheralState,
        ]
      )
      if characteristic.isNotifying {
        audioSessionCoordinator.trace(
          stage: "MAIN_NOTIFY_ENABLED",
          caller: "Aiv0BleControlBridge.notificationRefresh",
          values: ["peripheralState": peripheralState]
        )
      }
      emitStatus()
      refreshMainNotificationSubscription()
      return
    }
    guard error == nil, characteristic.isNotifying else {
      failDiscovery("Không bật được thông báo MAIN của H20.")
      return
    }
    lastNotificationRecovery = "initial • peripheral=\(peripheralState) • notify=\(notificationState)"
    audioSessionCoordinator.trace(
      stage: "ble_main_notification_state_updated",
      caller: "Aiv0BleControlBridge.initial",
      message: notificationState,
      values: ["peripheralState": peripheralState]
    )
    audioSessionCoordinator.trace(
      stage: "MAIN_NOTIFY_ENABLED",
      caller: "Aiv0BleControlBridge.initial",
      values: ["peripheralState": peripheralState]
    )
    emitStatus()
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
      lastMainTransportSource = "ble"
      if !duplicate,
        bytes.count == 12,
        bytes[0] == 0x01,
        bytes[1] == 0x01,
        bytes[3] == 0x01
      {
        audioSessionCoordinator.notePhysicalMain(rawHex: rawHex, source: "ble")
        let packetSequence = Int(bytes[2])
        audioSessionCoordinator.trace(
          stage: "MAIN_EVENT_DELIVERY_ATTEMPT",
          caller: "Aiv0BleControlBridge.eventChannel",
          message: rawHex,
          values: [
            "eventSinkAttached": eventSink != nil,
            "sequence": packetSequence,
            "transportSource": "ble",
          ]
        )
      }
      eventSink?([
        "type": "button",
        "bytes": bytes.map { Int($0) },
        "deviceId": peripheral.identifier.uuidString,
        "duplicate": duplicate,
        "transportSource": "ble",
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
    if let peripheral = connectedPeripheral {
      requestPeripheralDisconnect(
        peripheral,
        caller: "Aiv0BleControlBridge.failDiscovery",
        code: "discovery_failed"
      )
    }
  }
}
