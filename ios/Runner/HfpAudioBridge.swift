import AVFoundation
import Flutter
import Foundation

/// Selects an HFP microphone already connected in iOS Settings. iOS does not
/// expose public APIs for pairing or forcing a Classic Bluetooth profile link,
/// so `connect` means selecting an available AVAudioSession input.
final class HfpAudioBridge: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let audioSession = AVAudioSession.sharedInstance()
  private var eventSink: FlutterEventSink?
  private var selectedInputId: String?
  private var selectedInputName: String?
  private var phase = "idle"
  private var message: String?
  private var routeActive = false
  private var routeActivationGeneration = 0
  private var notificationTokens: [NSObjectProtocol] = []
  private var disposed = false

  init(messenger: FlutterBinaryMessenger) {
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
    try audioSession.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
    )
    if activate {
      try audioSession.setActive(true, options: [])
    }
  }

  private func bluetoothInputs() -> [AVAudioSessionPortDescription] {
    (audioSession.availableInputs ?? []).filter {
      $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
    }
  }

  private func findDevices(_ result: @escaping FlutterResult) {
    do {
      // Discovery must not activate the HFP route. Activating `.voiceChat`
      // while merely listing inputs can switch the H20 Bluetooth profile and
      // briefly drop its independent BLE control link. The session category is
      // prepared by `initialize`; discovery only reads `availableInputs` and
      // defers every route mutation until connect or startAudioRoute.
      let currentIds = Set(audioSession.currentRoute.inputs.map(\.uid))
      let inputs = bluetoothInputs()
      phase = inputs.isEmpty ? "idle" : "ready"
      message = inputs.isEmpty
        ? "iOS chưa thấy mic HFP. Hãy kết nối H20 trong Cài đặt Bluetooth rồi thử lại."
        : "Đã tìm thấy \(inputs.count) mic Bluetooth khả dụng."
      emitStatus()
      result(inputs.map { input in
        [
          "id": input.uid,
          "name": input.portName,
          "isConnected": currentIds.contains(input.uid) || selectedInputId == input.uid,
        ] as [String: Any]
      })
    } catch {
      fail(result, code: "HFP_LIST_FAILED", error: error)
    }
  }

  private func connect(deviceId: String?, result: @escaping FlutterResult) {
    guard let deviceId = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines),
      !deviceId.isEmpty
    else {
      result(FlutterError(code: "INVALID_DEVICE", message: "Thiếu mã mic HFP.", details: nil))
      return
    }
    do {
      phase = "connecting"
      message = "Đang chọn mic HFP trên iOS…"
      emitStatus()
      // Remember the preferred H20 input without opening the voice route yet.
      // Activating HFP during app startup can force a Bluetooth profile switch
      // while CoreBluetooth is still settling. `startAudioRoute` activates and
      // verifies the route only when recognition is about to begin.
      try configureSession(activate: false)
      guard let input = bluetoothInputs().first(where: { $0.uid == deviceId }) else {
        throw HfpBridgeError.inputUnavailable
      }
      try audioSession.setPreferredInput(input)
      selectedInputId = input.uid
      selectedInputName = input.portName
      phase = "ready"
      message = "Mic HFP đã sẵn sàng trên iOS."
      emitStatus()
      result(nil)
    } catch {
      fail(result, code: "HFP_CONNECT_FAILED", error: error)
    }
  }

  private func disconnect(_ result: @escaping FlutterResult) {
    do {
      routeActivationGeneration += 1
      routeActive = false
      try audioSession.setPreferredInput(nil)
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
    do {
      try configureSession(activate: true)
      if let selectedInputId {
        guard let selected = bluetoothInputs().first(where: { $0.uid == selectedInputId }) else {
          throw HfpBridgeError.inputUnavailable
        }
        try audioSession.setPreferredInput(selected)
        selectedInputName = selected.portName
      }
      routeActive = false
      phase = "connecting"
      message = "Đang kích hoạt đường mic HFP…"
      emitStatus()
      waitForActiveBluetoothInput(
        generation: activationGeneration,
        attemptsRemaining: 15,
        result: result
      )
    } catch {
      fail(result, code: "HFP_ROUTE_UNAVAILABLE", error: error)
    }
  }

  private func waitForActiveBluetoothInput(
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
    if let hfpInput = activeBluetoothInput() {
      selectedInputId = hfpInput.uid
      selectedInputName = hfpInput.portName
      routeActive = true
      phase = "recording"
      message = "Đang dùng mic HFP cho Apple Native Speech hoặc Batch dự phòng."
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
        result(nil)
      }
      return
    }
    guard attemptsRemaining > 0 else {
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
        result: result
      )
    }
  }

  private func stopAudioRoute() {
    routeActivationGeneration += 1
    routeActive = false
    if let selectedInputId,
      bluetoothInputs().contains(where: { $0.uid == selectedInputId })
    {
      phase = "ready"
      message = "Mic HFP đã kết nối; sẵn sàng cho lượt tiếp theo."
    } else {
      phase = "idle"
      message = nil
    }
    emitStatus()
  }

  private func activeBluetoothInput() -> AVAudioSessionPortDescription? {
    audioSession.currentRoute.inputs.first {
      $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
    }
  }

  private func refreshStatus() {
    if routeActive, let active = activeBluetoothInput() {
      selectedInputId = active.uid
      selectedInputName = active.portName
      phase = "recording"
      message = "Đang dùng mic HFP cho Apple Native Speech hoặc Batch dự phòng."
    } else if let selectedInputId,
      bluetoothInputs().contains(where: { $0.uid == selectedInputId })
    {
      phase = "ready"
      message = "Mic HFP đã kết nối; sẵn sàng."
    } else if let active = activeBluetoothInput() {
      selectedInputId = active.uid
      selectedInputName = active.portName
      phase = "ready"
      message = "iOS đang định tuyến qua mic Bluetooth."
    } else {
      routeActive = false
      phase = "idle"
      if selectedInputId != nil {
        message = "Mic HFP không còn khả dụng; hãy kiểm tra Bluetooth iOS."
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

  var errorDescription: String? {
    switch self {
    case .inputUnavailable:
      return "Mic HFP không còn khả dụng. Hãy kết nối lại trong Cài đặt Bluetooth iOS."
    case .routeUnavailable:
      return "iOS chưa định tuyến được mic Bluetooth HFP."
    case .routeCancelled:
      return "Yêu cầu mở mic HFP đã được thay thế hoặc hủy."
    }
  }
}
