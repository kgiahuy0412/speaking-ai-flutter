import AVFoundation
import Flutter
import Foundation

struct IOSHfpRoutePolicy {
  static let categoryOptions: AVAudioSession.CategoryOptions = [.allowBluetooth]

  static func isHfpInput(_ portType: AVAudioSession.Port) -> Bool {
    portType == .bluetoothHFP
  }

  static func isHfpOutput(_ portType: AVAudioSession.Port) -> Bool {
    portType == .bluetoothHFP
  }

  static func isTwoWayHfpRoute(
    inputTypes: [AVAudioSession.Port],
    outputTypes: [AVAudioSession.Port]
  ) -> Bool {
    inputTypes.contains { isHfpInput($0) }
      && outputTypes.contains { isHfpOutput($0) }
  }
}

/// Owns one app-session HFP lease independently from individual utterances.
/// `startAudioRoute` may be requested by conversation, lessons, and MAIN, but
/// they all share the same native H20 route and must not repeatedly acquire or
/// release AVAudioSession while the device remains selected.
struct IOSHfpRouteLeaseState {
  private(set) var isHeld = false

  mutating func acquireIfNeeded() -> Bool {
    guard !isHeld else { return false }
    isHeld = true
    return true
  }

  mutating func releaseIfHeld() -> Bool {
    guard isHeld else { return false }
    isHeld = false
    return true
  }
}

enum IOSHfpIdleRouteReleaseStep: Equatable {
  case complete
  case wait
  case timedOut
}

/// `setActive(false)` completes before `currentRoute` necessarily leaves HFP.
/// BLE must use the authoritative route state rather than a fixed delay, or a
/// slow H20/iPhone handoff starts GATT while SCO still owns the radio.
struct IOSHfpIdleRouteReleasePolicy {
  static func nextStep(
    hasTwoWayHfpRoute: Bool,
    attemptsRemaining: Int
  ) -> IOSHfpIdleRouteReleaseStep {
    guard hasTwoWayHfpRoute else { return .complete }
    return attemptsRemaining > 0 ? .wait : .timedOut
  }
}

/// Selects an HFP microphone already connected in iOS Settings. iOS does not
/// expose public APIs for pairing or forcing a Classic Bluetooth profile link,
/// so `connect` means selecting an available AVAudioSession input.
final class HfpAudioBridge: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let audioSessionCoordinator: IOSAudioSessionCoordinator
  private var audioSession: AVAudioSession { audioSessionCoordinator.session }
  private var eventSink: FlutterEventSink?
  private var selectedInputId: String?
  private var selectedInputName: String?
  private var phase = "idle"
  private var message: String?
  private var routeActive = false
  private var routeActivationGeneration = 0
  private var hfpRouteLease = IOSHfpRouteLeaseState()
  private var notificationTokens: [NSObjectProtocol] = []
  private var disposed = false

  init(
    messenger: FlutterBinaryMessenger,
    audioSessionCoordinator: IOSAudioSessionCoordinator
  ) {
    self.audioSessionCoordinator = audioSessionCoordinator
    methodChannel = FlutterMethodChannel(name: "ailingo_hfp_audio", binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: "ailingo_hfp_audio/events", binaryMessenger: messenger)
    super.init()
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    eventChannel.setStreamHandler(self)
    observeAudioSession()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !disposed || call.method == "dispose" else {
      result(FlutterError(code: "HFP_DISPOSED", message: "Cầu nối HFP đã đóng.", details: nil))
      return
    }
    switch call.method {
    case "initialize":
      do {
        try configureSession(activate: false)
        refreshStatus()
        result(snapshot())
      } catch {
        fail(result, code: "HFP_INITIALIZE_FAILED", error: error)
      }
    case "requestPermissions":
      // Classic Bluetooth audio routes are managed by iOS. CoreBluetooth
      // permission is requested separately by the AIV0 BLE control bridge.
      result(true)
    case "findDevices":
      findDevices(result)
    case "connect":
      let arguments = call.arguments as? [String: Any]
      connect(deviceId: arguments?["deviceId"] as? String, result: result)
    case "disconnect":
      disconnect(result)
    case "startAudioRoute":
      startAudioRoute(result)
    case "stopAudioRoute":
      stopAudioRoute()
      result(nil)
    case "dispose":
      dispose()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configureSession(activate: Bool) throws {
    try audioSessionCoordinator.configureHfp(
      activate: activate,
      preferredInput: nil,
      caller: "HfpAudioBridge.configureSession"
    )
  }

  private func bluetoothInputs() -> [AVAudioSessionPortDescription] {
    (audioSession.availableInputs ?? []).filter {
      IOSHfpRoutePolicy.isHfpInput($0.portType)
    }
  }

  private func findDevices(_ result: @escaping FlutterResult) {
    do {
      // iOS can keep a connected headset out of availableInputs until a
      // record-capable session is active. Wake the voice profile, then give
      // AVAudioSession a bounded window to publish the bluetoothHFP input.
      phase = "scanning"
      message = "Đang yêu cầu iOS mở profile âm thanh HFP…"
      emitStatus()
      try configureSession(activate: true)
      waitForDiscoverableInputs(attemptsRemaining: 15, result: result)
    } catch {
      fail(result, code: "HFP_LIST_FAILED", error: error)
    }
  }

  private func waitForDiscoverableInputs(
    attemptsRemaining: Int,
    result: @escaping FlutterResult
  ) {
    let inputs = bluetoothInputs()
    if !inputs.isEmpty || attemptsRemaining <= 0 {
      let activeInput = activeTwoWayHfpInput()
      if let activeInput {
        selectedInputId = activeInput.uid
        selectedInputName = activeInput.portName
        routeActive = true
        phase = "ready"
        message = "Đã xác nhận mic và loa H20 trên route bluetoothHFP."
      } else {
        routeActive = false
        phase = "idle"
        message = inputs.isEmpty
          ? "iOS chưa công bố đầu vào bluetoothHFP dù H20 đang ghép đôi. Hãy tắt/bật lại H20 rồi thử lại."
          : "Đã tìm thấy \(inputs.count) mic HFP; hãy chọn H20 để mở route hai chiều."
        if inputs.isEmpty {
          audioSessionCoordinator.trace(
            stage: "hfp_inputs_unavailable",
            caller: "HfpAudioBridge.findDevices"
          )
        }
      }
      emitStatus()
      let currentIds = Set(audioSession.currentRoute.inputs.map(\.uid))
      result(inputs.map { input in
        [
          "id": input.uid,
          "name": input.portName,
          "isConnected": currentIds.contains(input.uid) && hasActiveHfpOutput(),
        ] as [String: Any]
      })
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
      guard let self, !self.disposed else {
        result(
          FlutterError(
            code: "HFP_ROUTE_CANCELLED",
            message: HfpBridgeError.routeCancelled.localizedDescription,
            details: nil
          )
        )
        return
      }
      self.waitForDiscoverableInputs(
        attemptsRemaining: attemptsRemaining - 1,
        result: result
      )
    }
  }

  private func connect(deviceId: String?, result: @escaping FlutterResult) {
    guard let deviceId = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines),
      !deviceId.isEmpty
    else {
      result(FlutterError(code: "INVALID_DEVICE", message: "Thiếu mã mic HFP.", details: nil))
      return
    }
    routeActivationGeneration += 1
    let activationGeneration = routeActivationGeneration
    do {
      phase = "connecting"
      message = "Đang chọn mic HFP trên iOS…"
      emitStatus()
      try configureSession(activate: true)
      guard let input = bluetoothInputs().first(where: { $0.uid == deviceId }) else {
        throw HfpBridgeError.inputUnavailable
      }
      try audioSessionCoordinator.configureHfp(
        activate: true,
        preferredInput: input,
        caller: "HfpAudioBridge.connect"
      )
      selectedInputId = input.uid
      selectedInputName = input.portName
      routeActive = false
      phase = "connecting"
      message = "Đang xác nhận mic và loa H20 trên route bluetoothHFP…"
      emitStatus()
      waitForActiveBluetoothInput(
        generation: activationGeneration,
        attemptsRemaining: 15,
        recording: false,
        result: result
      )
    } catch {
      fail(result, code: "HFP_CONNECT_FAILED", error: error)
    }
  }

  private func disconnect(_ result: @escaping FlutterResult) {
    do {
      routeActivationGeneration += 1
      routeActive = false
      releaseHfpSessionLease(
        caller: "HfpAudioBridge.disconnect"
      )
      try audioSessionCoordinator.clearPreferredInput(
        caller: "HfpAudioBridge.disconnect"
      )
      selectedInputId = nil
      selectedInputName = nil
      phase = "idle"
      message = "Đã trở về mic mặc định của iPhone/iPad."
      emitStatus()
      result(nil)
    } catch {
      fail(result, code: "HFP_DISCONNECT_FAILED", error: error)
    }
  }

  private func startAudioRoute(_ result: @escaping FlutterResult) {
    routeActivationGeneration += 1
    let activationGeneration = routeActivationGeneration
    let acquiredLeaseForThisAttempt = acquireHfpSessionLease(
      caller: "HfpAudioBridge.startAudioRoute"
    )
    // H20 can already own a confirmed two-way HFP route after Settings or a
    // previous MAIN turn. Re-applying the category, active flag and preferred
    // input here makes iOS renegotiate the Classic Bluetooth profile. On the
    // combined H20 firmware that renegotiation also interrupts the BLE control
    // link, so the physical MAIN packet is followed by an unnecessary reconnect.
    if let activeInput = activeTwoWayHfpInput(),
      selectedInputId == nil || selectedInputId == activeInput.uid
    {
      selectedInputId = activeInput.uid
      selectedInputName = activeInput.portName
      routeActive = true
      phase = "recording"
      message = "Đang dùng lại mic và loa H20 trên route bluetoothHFP hai chiều."
      emitStatus()
      result(snapshot())
      return
    }
    do {
      try configureSession(activate: true)
      if let selectedInputId {
        guard let selected = bluetoothInputs().first(where: { $0.uid == selectedInputId }) else {
          throw HfpBridgeError.inputUnavailable
        }
        try audioSessionCoordinator.configureHfp(
          activate: true,
          preferredInput: selected,
          caller: "HfpAudioBridge.startAudioRoute"
        )
        selectedInputName = selected.portName
      }
      routeActive = false
      phase = "connecting"
      message = "Đang kích hoạt đường mic HFP…"
      emitStatus()
      waitForActiveBluetoothInput(
        generation: activationGeneration,
        attemptsRemaining: 15,
        recording: true,
        releaseLeaseOnFailure: acquiredLeaseForThisAttempt,
        result: result
      )
    } catch {
      if acquiredLeaseForThisAttempt {
        releaseHfpSessionLease(caller: "HfpAudioBridge.startAudioRoute.failed")
      }
      fail(result, code: "HFP_ROUTE_UNAVAILABLE", error: error)
    }
  }

  private func waitForActiveBluetoothInput(
    generation: Int,
    attemptsRemaining: Int,
    recording: Bool,
    releaseLeaseOnFailure: Bool = false,
    result: @escaping FlutterResult
  ) {
    guard !disposed, generation == routeActivationGeneration else {
      result(
        FlutterError(
          code: "HFP_ROUTE_CANCELLED",
          message: HfpBridgeError.routeCancelled.localizedDescription,
          details: nil
        )
      )
      return
    }
    if let hfpInput = activeTwoWayHfpInput() {
      selectedInputId = hfpInput.uid
      selectedInputName = hfpInput.portName
      routeActive = true
      phase = recording ? "recording" : "ready"
      message = recording
        ? "Đang dùng mic và loa H20 trên route bluetoothHFP hai chiều."
        : "Đã xác nhận mic và loa H20 trên route bluetoothHFP."
      emitStatus()
      // Let AVAudioSession finish settling before AVAudioEngine opens its tap.
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
        guard let self,
          !self.disposed,
          generation == self.routeActivationGeneration
        else {
          result(
            FlutterError(
              code: "HFP_ROUTE_CANCELLED",
              message: HfpBridgeError.routeCancelled.localizedDescription,
              details: nil
            )
          )
          return
        }
        if !recording {
          // `connect` only verifies and remembers the paired HFP input. Do not
          // leave SCO active while idle: H20 exposes BLE and Classic Bluetooth
          // on the same firmware and an always-open voice profile makes its
          // GATT control link disconnect/reconnect continuously on iOS.
          self.audioSessionCoordinator.releaseAudioSessionIfIdle(
            caller: "HfpAudioBridge.connectVerified"
          )
          self.waitForIdleBluetoothRoute(
            generation: generation,
            attemptsRemaining: 30,
            result: result
          )
          return
        }
        result(self.snapshot())
      }
      return
    }
    guard attemptsRemaining > 0 else {
      if recording && releaseLeaseOnFailure {
        releaseHfpSessionLease(
          caller: "HfpAudioBridge.waitForActiveBluetoothInput.timeout"
        )
      }
      fail(result, code: "HFP_ROUTE_UNAVAILABLE", error: HfpBridgeError.routeUnavailable)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
      guard let self else {
        result(
          FlutterError(
            code: "HFP_ROUTE_CANCELLED",
            message: HfpBridgeError.routeCancelled.localizedDescription,
            details: nil
          )
        )
        return
      }
      self.waitForActiveBluetoothInput(
        generation: generation,
        attemptsRemaining: attemptsRemaining - 1,
        recording: recording,
        releaseLeaseOnFailure: releaseLeaseOnFailure,
        result: result
      )
    }
  }

  private func stopAudioRoute() {
    routeActivationGeneration += 1
    // This is an utterance boundary, not a device disconnect. Keeping the
    // verified HFP route prevents iOS from renegotiating the Classic Bluetooth
    // voice profile after every sentence, which was dropping the independent
    // BLE GATT channel that carries physical MAIN presses.
    if let activeInput = activeTwoWayHfpInput(),
      selectedInputId == nil || selectedInputId == activeInput.uid
    {
      selectedInputId = activeInput.uid
      selectedInputName = activeInput.portName
      routeActive = true
      phase = "ready"
      message = "Mic và loa H20 được giữ ổn định giữa các lượt nói."
    } else {
      routeActive = false
      phase = "idle"
      message = selectedInputId == nil
        ? nil
        : "Đã chọn mic HFP; route sẽ được xác nhận ở lượt nói tiếp theo."
    }
    emitStatus()
  }

  private func waitForIdleBluetoothRoute(
    generation: Int,
    attemptsRemaining: Int,
    result: @escaping FlutterResult
  ) {
    guard !disposed, generation == routeActivationGeneration else {
      result(
        FlutterError(
          code: "HFP_ROUTE_CANCELLED",
          message: HfpBridgeError.routeCancelled.localizedDescription,
          details: nil
        )
      )
      return
    }
    let step = IOSHfpIdleRouteReleasePolicy.nextStep(
      hasTwoWayHfpRoute: activeTwoWayHfpInput() != nil,
      attemptsRemaining: attemptsRemaining
    )
    switch step {
    case .complete:
      routeActive = false
      phase = "idle"
      message = "Đã chọn mic HFP; SCO đã nhả và BLE có thể kết nối an toàn."
      audioSessionCoordinator.trace(
        stage: "hfp_idle_route_confirmed",
        caller: "HfpAudioBridge.connectVerified"
      )
      emitStatus()
      result(snapshot())
    case .wait:
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
        guard let self else {
          result(
            FlutterError(
              code: "HFP_ROUTE_CANCELLED",
              message: HfpBridgeError.routeCancelled.localizedDescription,
              details: nil
            )
          )
          return
        }
        self.waitForIdleBluetoothRoute(
          generation: generation,
          attemptsRemaining: attemptsRemaining - 1,
          result: result
        )
      }
    case .timedOut:
      routeActive = true
      phase = "error"
      message = HfpBridgeError.routeReleaseTimedOut.localizedDescription
      audioSessionCoordinator.trace(
        stage: "hfp_idle_route_release_timeout",
        caller: "HfpAudioBridge.connectVerified",
        code: "HFP_ROUTE_RELEASE_TIMEOUT"
      )
      emitStatus()
      result(
        FlutterError(
          code: "HFP_ROUTE_RELEASE_TIMEOUT",
          message: message,
          details: nil
        )
      )
    }
  }

  @discardableResult
  private func acquireHfpSessionLease(caller: String) -> Bool {
    guard hfpRouteLease.acquireIfNeeded() else { return false }
    audioSessionCoordinator.acquireHfpRoute(caller: caller)
    return true
  }

  private func releaseHfpSessionLease(caller: String) {
    guard hfpRouteLease.releaseIfHeld() else { return }
    audioSessionCoordinator.releaseHfpRoute(caller: caller)
  }

  private func activeHfpInput() -> AVAudioSessionPortDescription? {
    audioSession.currentRoute.inputs.first {
      IOSHfpRoutePolicy.isHfpInput($0.portType)
    }
  }

  private func hasActiveHfpOutput() -> Bool {
    audioSession.currentRoute.outputs.contains {
      IOSHfpRoutePolicy.isHfpOutput($0.portType)
    }
  }

  private func activeTwoWayHfpInput() -> AVAudioSessionPortDescription? {
    guard hasActiveHfpOutput() else { return nil }
    return activeHfpInput()
  }

  private func refreshStatus() {
    if phase == "recording", let active = activeTwoWayHfpInput() {
      selectedInputId = active.uid
      selectedInputName = active.portName
      phase = "recording"
      message = "Đang dùng mic và loa H20 trên route bluetoothHFP hai chiều."
    } else if let selectedInputId,
      let active = activeTwoWayHfpInput(),
      active.uid == selectedInputId
    {
      routeActive = true
      phase = "ready"
      message = "Mic và loa H20 đã được xác nhận trên currentRoute."
    } else if let active = activeTwoWayHfpInput() {
      selectedInputId = active.uid
      selectedInputName = active.portName
      routeActive = true
      phase = "ready"
      message = "iOS đang định tuyến mic và loa qua bluetoothHFP."
    } else {
      routeActive = false
      phase = "idle"
      if selectedInputId != nil {
        message = bluetoothInputs().contains(where: { $0.uid == selectedInputId })
          ? "Đã chọn mic HFP; route hiện chưa hoạt động."
          : "Mic HFP không còn khả dụng; hãy kiểm tra Bluetooth iOS."
      }
    }
    emitStatus()
  }

  private func observeAudioSession() {
    let center = NotificationCenter.default
    notificationTokens.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: audioSession,
        queue: .main
      ) { [weak self] _ in self?.refreshStatus() }
    )
    notificationTokens.append(
      center.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification,
        object: audioSession,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        do {
          try self.configureSession(activate: self.routeActive)
          self.refreshStatus()
        } catch {
          self.phase = "error"
          self.message = error.localizedDescription
          self.emitStatus()
        }
      }
    )
  }

  private func routeDescription() -> String {
    let route = audioSession.currentRoute
    let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }
    let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
    return "in=[\(inputs.joined(separator: ", "))] out=[\(outputs.joined(separator: ", "))]"
  }

  private func snapshot() -> [String: Any] {
    var value: [String: Any] = [
      "type": "status",
      "phase": phase,
      "sampleRate": Int(audioSession.sampleRate.rounded()),
      "routeActive": routeActive,
      "audioRoute": routeDescription(),
      "hasSelectedInput": selectedInputId != nil,
    ]
    if let selectedInputId { value["deviceId"] = selectedInputId }
    if let selectedInputName { value["deviceName"] = selectedInputName }
    if let message { value["message"] = message }
    if let input = audioSession.currentRoute.inputs.first {
      value["inputDeviceName"] = input.portName
    }
    if let output = audioSession.currentRoute.outputs.first {
      value["outputDeviceName"] = output.portName
    }
    return value
  }

  private func emitStatus() {
    guard !disposed else { return }
    eventSink?(snapshot())
  }

  private func fail(_ result: FlutterResult, code: String, error: Error) {
    phase = "error"
    message = error.localizedDescription
    routeActive = false
    emitStatus()
    result(FlutterError(code: code, message: error.localizedDescription, details: nil))
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
    stopAudioRoute()
    releaseHfpSessionLease(caller: "HfpAudioBridge.dispose")
    disposed = true
    notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    notificationTokens.removeAll()
    eventSink = nil
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
  }
}

private enum HfpBridgeError: LocalizedError {
  case inputUnavailable
  case routeUnavailable
  case routeCancelled
  case routeReleaseTimedOut

  var errorDescription: String? {
    switch self {
    case .inputUnavailable:
      return "Mic HFP không còn khả dụng. Hãy kết nối lại trong Cài đặt Bluetooth iOS."
    case .routeUnavailable:
      return "iOS chưa định tuyến đồng thời mic và loa qua bluetoothHFP."
    case .routeCancelled:
      return "Yêu cầu mở mic HFP đã được thay thế hoặc hủy."
    case .routeReleaseTimedOut:
      return "HFP/SCO vẫn đang hoạt động; HOMI chưa mở BLE để tránh làm gián đoạn mic H20."
    }
  }
}
