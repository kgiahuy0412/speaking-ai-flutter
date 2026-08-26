import AVFoundation
import Foundation

enum IOSAudioInputTarget: String {
  case builtInMic
  case hfp
}

/// The single writer for AVAudioSession during an iOS MAIN turn.
///
/// HFP, prompt playback and speech capture may inspect the shared session, but
/// every mutation is routed through this coordinator. It also keeps a bounded
/// per-turn timeline so a device build can identify the exact caller that
/// changed a route or ended a turn.
final class IOSAudioSessionCoordinator: NSObject {
  let session = AVAudioSession.sharedInstance()

  private var routeChangeToken: NSObjectProtocol?
  private var interruptionToken: NSObjectProtocol?
  private var traceSink: (([String: Any]) -> Void)?
  private var traceBuffer: [[String: Any]] = []
  private var pendingTurnId: String?
  private var pendingTurnStartedAt: Date?
  private var activeTurnId: String?
  private var activeTurnStartedAt: Date?
  private var sequence = 0
  private var turnTimeout: DispatchWorkItem?
  private(set) var isMainTurnActive = false
  private(set) var isBackgroundLearningEnabled = false
  var onMainTurnEnded: (() -> Void)?
  var onBackgroundLearningEvent: (([String: Any]) -> Void)?

  override init() {
    super.init()
    routeChangeToken = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: session,
      queue: .main
    ) { [weak self] notification in
      self?.recordRouteChange(notification)
    }
    interruptionToken = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: session,
      queue: .main
    ) { [weak self] notification in
      self?.recordInterruption(notification)
    }
  }

  func setBackgroundLearningEnabled(_ enabled: Bool) {
    isBackgroundLearningEnabled = enabled
    trace(
      stage: enabled ? "background_learning_enabled" : "background_learning_disabled",
      caller: "BackgroundLearningBridge"
    )
    if !enabled {
      releaseAudioSessionIfIdle(caller: "BackgroundLearningBridge.stop")
    }
  }

  func notePhysicalMain(rawHex: String) {
    if pendingTurnId == nil && !isMainTurnActive {
      pendingTurnId = makeTurnId()
      pendingTurnStartedAt = Date()
      sequence = 0
    }
    trace(stage: "main_raw_received", caller: "Aiv0BleControlBridge", message: rawHex)
  }

  @discardableResult
  func beginMainTurn(source: String) -> String {
    if isMainTurnActive, let activeTurnId {
      trace(stage: "main_turn_reused", caller: source)
      return activeTurnId
    }

    let now = Date()
    let pendingIsRecent = pendingTurnStartedAt.map {
      now.timeIntervalSince($0) <= 5
    } ?? false
    if pendingIsRecent, let pendingTurnId {
      activeTurnId = pendingTurnId
      activeTurnStartedAt = pendingTurnStartedAt
    } else {
      activeTurnId = makeTurnId()
      activeTurnStartedAt = now
      sequence = 0
    }
    pendingTurnId = nil
    pendingTurnStartedAt = nil
    isMainTurnActive = true
    trace(stage: "main_turn_started", caller: source)
    scheduleSafetyTimeout()
    return activeTurnId!
  }

  func endMainTurn(reason: String, caller: String) {
    guard isMainTurnActive else {
      // An initial Dart pause happens after a physical packet and before the
      // actual turn begins. Do not erase that pending packet timeline.
      trace(stage: "main_turn_end_ignored", caller: caller, message: reason)
      return
    }
    trace(stage: "main_turn_ended", caller: caller, message: reason)
    turnTimeout?.cancel()
    turnTimeout = nil
    isMainTurnActive = false
    activeTurnId = nil
    activeTurnStartedAt = nil
    sequence = 0
    // A two-way HFP/SCO route is only owned for the duration of a MAIN turn.
    // Keeping AVAudioSession active after the turn leaves H20 in its voice
    // profile and the combined firmware repeatedly drops its BLE GATT link.
    // Release the voice profile before resuming the deferred BLE reconnect.
    releaseAudioSessionIfIdle(caller: "IOSAudioSessionCoordinator.endMainTurn")
    onMainTurnEnded?()
  }

  func attachTraceSink(_ sink: @escaping ([String: Any]) -> Void) {
    traceSink = sink
    traceBuffer.forEach(sink)
  }

  func detachTraceSink() {
    traceSink = nil
  }

  func eventMetadata() -> [String: Any] {
    let now = Date()
    let startedAt = activeTurnStartedAt ?? pendingTurnStartedAt ?? now
    var values: [String: Any] = [
      "elapsedMs": max(0, Int(now.timeIntervalSince(startedAt) * 1_000)),
      "audioRoute": routeDescription(),
    ]
    if let turnId = activeTurnId ?? pendingTurnId {
      values["turnId"] = turnId
    }
    return values
  }

  @discardableResult
  func trace(
    stage: String,
    caller: String,
    code: String? = nil,
    message: String? = nil,
    values: [String: Any] = [:]
  ) -> [String: Any] {
    let now = Date()
    sequence += 1
    let startedAt = activeTurnStartedAt ?? pendingTurnStartedAt ?? now
    var payload: [String: Any] = [
      "type": "speech.stage",
      "stage": stage,
      "caller": caller,
      "sequence": sequence,
      "elapsedMs": max(0, Int(now.timeIntervalSince(startedAt) * 1_000)),
      "eventEpochMs": Int(now.timeIntervalSince1970 * 1_000),
      "audioRoute": routeDescription(),
    ]
    if let turnId = activeTurnId ?? pendingTurnId {
      payload["turnId"] = turnId
    }
    if let code { payload["code"] = code }
    if let message { payload["message"] = message }
    payload.merge(values) { _, new in new }
    traceBuffer.append(payload)
    if traceBuffer.count > 200 {
      traceBuffer.removeFirst(traceBuffer.count - 200)
    }
    traceSink?(payload)
    return payload
  }

  func preparePrompt(preferredHfpInput: AVAudioSessionPortDescription?, caller: String) throws -> Bool {
    trace(stage: "prompt_audio_prepare", caller: caller)
    if hasTwoWayHfpRoute() {
      trace(stage: "prompt_audio_route_reused", caller: caller)
      return true
    }
    if let preferredHfpInput {
      try ensureCategory(
        mode: .voiceChat,
        options: IOSHfpRoutePolicy.categoryOptions,
        caller: caller
      )
      try ensureActive(caller: caller)
      try ensurePreferredInput(preferredHfpInput, caller: caller)
      try ensureOutputOverride(.none, caller: caller)
      return true
    }
    try ensureCategory(
      mode: .default,
      options: [.defaultToSpeaker, .duckOthers],
      caller: caller
    )
    try ensurePreferredInput(nil, caller: caller)
    try ensureActive(caller: caller)
    try ensureOutputOverride(.speaker, caller: caller)
    return false
  }

  func releasePrompt(usedHfp _: Bool, caller: String) {
    trace(stage: "prompt_audio_release", caller: caller)
    guard !isMainTurnActive else {
      trace(stage: "prompt_audio_release_preserved_for_main", caller: caller)
      return
    }
    releaseAudioSessionIfIdle(caller: caller)
  }

  /// Releases a record-capable route when no MAIN turn owns it.
  ///
  /// The selected HFP UID is kept by `HfpAudioBridge`; only the live SCO/audio
  /// session is released. A later MAIN turn can therefore reactivate and
  /// verify the same H20 input without keeping BLE-hostile SCO open at idle.
  func releaseAudioSessionIfIdle(caller: String) {
    guard !isMainTurnActive else {
      trace(stage: "audio_session_release_preserved_for_main", caller: caller)
      return
    }
    trace(stage: "audio_session_release_requested", caller: caller)
    do {
      try ensureOutputOverride(.none, caller: caller)
      try setActive(false, notifyOthers: true, caller: caller)
      trace(stage: "audio_session_release_completed", caller: caller)
    } catch {
      let nsError = error as NSError
      trace(
        stage: "audio_session_release_failed",
        caller: caller,
        code: "\(nsError.domain):\(nsError.code)",
        message: error.localizedDescription
      )
    }
  }

  func configureHfp(activate: Bool, preferredInput: AVAudioSessionPortDescription?, caller: String) throws {
    try ensureCategory(
      mode: .voiceChat,
      options: IOSHfpRoutePolicy.categoryOptions,
      caller: caller
    )
    if activate {
      try ensureActive(caller: caller)
    }
    if let preferredInput {
      try ensurePreferredInput(preferredInput, caller: caller)
    }
  }

  func clearPreferredInput(caller: String) throws {
    try ensurePreferredInput(nil, caller: caller)
  }

  func prepareCapture(target: IOSAudioInputTarget, caller: String) throws {
    trace(stage: "audio_session_prepare", caller: caller, values: ["audioSource": target.rawValue])
    switch target {
    case .hfp:
      if hasTwoWayHfpRoute() {
        trace(stage: "audio_session_active", caller: caller, values: ["audioSource": target.rawValue])
        trace(stage: "route_confirmed", caller: caller, values: ["audioSource": target.rawValue])
        return
      }
      guard let input = currentOrAvailableInput(portType: .bluetoothHFP) else {
        throw IOSAudioSessionCoordinatorError.hfpInputUnavailable
      }
      try configureHfp(activate: true, preferredInput: input, caller: caller)
    case .builtInMic:
      guard let input = currentOrAvailableInput(portType: .builtInMic) else {
        throw IOSAudioSessionCoordinatorError.builtInMicUnavailable
      }
      try ensureCategory(mode: .voiceChat, options: [.defaultToSpeaker], caller: caller)
      try ensureActive(caller: caller)
      try ensurePreferredInput(input, caller: caller)
    }
    trace(stage: "audio_session_active", caller: caller, values: ["audioSource": target.rawValue])
  }

  func routeDescription() -> String {
    let inputs = session.currentRoute.inputs.map { "\($0.portType.rawValue):\($0.portName)" }
    let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
    return "in=[\(inputs.joined(separator: ", "))] out=[\(outputs.joined(separator: ", "))]"
  }

  func hasTwoWayHfpRoute() -> Bool {
    IOSHfpRoutePolicy.isTwoWayHfpRoute(
      inputTypes: session.currentRoute.inputs.map(\.portType),
      outputTypes: session.currentRoute.outputs.map(\.portType)
    )
  }

  func dispose() {
    turnTimeout?.cancel()
    turnTimeout = nil
    if let routeChangeToken {
      NotificationCenter.default.removeObserver(routeChangeToken)
    }
    routeChangeToken = nil
    if let interruptionToken {
      NotificationCenter.default.removeObserver(interruptionToken)
    }
    interruptionToken = nil
    traceSink = nil
    onMainTurnEnded = nil
    onBackgroundLearningEvent = nil
  }

  private func currentOrAvailableInput(portType: AVAudioSession.Port) -> AVAudioSessionPortDescription? {
    session.currentRoute.inputs.first { $0.portType == portType }
      ?? session.availableInputs?.first { $0.portType == portType }
  }

  private func ensureCategory(
    mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions,
    caller: String
  ) throws {
    guard session.category != .playAndRecord || session.mode != mode || session.categoryOptions != options else {
      trace(stage: "setCategory_skipped", caller: caller)
      return
    }
    trace(stage: "setCategory_requested", caller: caller, message: "playAndRecord/\(mode.rawValue)/\(options.rawValue)")
    try session.setCategory(.playAndRecord, mode: mode, options: options)
    trace(stage: "setCategory_completed", caller: caller)
  }

  private func ensureActive(caller: String) throws {
    try setActive(true, notifyOthers: false, caller: caller)
  }

  private func setActive(_ active: Bool, notifyOthers: Bool, caller: String) throws {
    trace(stage: active ? "setActive_true_requested" : "setActive_false_requested", caller: caller)
    try session.setActive(
      active,
      options: notifyOthers ? [.notifyOthersOnDeactivation] : []
    )
    trace(stage: active ? "setActive_true_completed" : "setActive_false_completed", caller: caller)
  }

  private func ensurePreferredInput(_ input: AVAudioSessionPortDescription?, caller: String) throws {
    if session.preferredInput?.uid == input?.uid {
      trace(stage: "setPreferredInput_skipped", caller: caller, message: input?.portName ?? "nil")
      return
    }
    trace(stage: "setPreferredInput_requested", caller: caller, message: input?.portName ?? "nil")
    try session.setPreferredInput(input)
    trace(stage: "setPreferredInput_completed", caller: caller, message: input?.portName ?? "nil")
  }

  private func ensureOutputOverride(_ port: AVAudioSession.PortOverride, caller: String) throws {
    trace(stage: "overrideOutput_requested", caller: caller, message: port == .speaker ? "speaker" : "none")
    try session.overrideOutputAudioPort(port)
    trace(stage: "overrideOutput_completed", caller: caller)
  }

  private func recordRouteChange(_ notification: Notification) {
    let rawReason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
    let previous = (notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)
      .map { routeDescription($0) } ?? "unknown"
    trace(
      stage: "routeChange",
      caller: "AVAudioSession",
      message: "reason=\(rawReason) before=\(previous) after=\(routeDescription())"
    )
  }

  private func recordInterruption(_ notification: Notification) {
    let rawType = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue ?? 0
    let rawReason = (notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? NSNumber)?.uintValue ?? 0
    let type = AVAudioSession.InterruptionType(rawValue: rawType)
    trace(
      stage: type == .began ? "audio_interruption_began" : "audio_interruption_ended",
      caller: "AVAudioSession",
      message: "reason=\(rawReason)"
    )
    guard isBackgroundLearningEnabled, type == .began else { return }

    // Locking the screen does not emit an AVAudioSession interruption while
    // the background audio mode remains active. Every real interruption that
    // reaches this observer (for example a call, Siri, an alarm, or competing
    // non-mixable audio) must pause the learning session.
    onBackgroundLearningEvent?([
      "type": "background.interrupted",
      "reason": "audio_session_interruption_\(rawReason)",
    ])
  }

  private func routeDescription(_ route: AVAudioSessionRouteDescription) -> String {
    let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }
    let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
    return "in=[\(inputs.joined(separator: ", "))] out=[\(outputs.joined(separator: ", "))]"
  }

  private func makeTurnId() -> String {
    "ios-main-\(Int(Date().timeIntervalSince1970 * 1_000))-\(UUID().uuidString.prefix(6))"
  }

  private func scheduleSafetyTimeout() {
    turnTimeout?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.endMainTurn(reason: "native_safety_timeout", caller: "IOSAudioSessionCoordinator")
    }
    turnTimeout = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: item)
  }
}

private enum IOSAudioSessionCoordinatorError: LocalizedError {
  case builtInMicUnavailable
  case hfpInputUnavailable

  var errorDescription: String? {
    switch self {
    case .builtInMicUnavailable:
      return "Không tìm thấy mic tích hợp của iPhone/iPad."
    case .hfpInputUnavailable:
      return "Không tìm thấy mic HFP đang kết nối."
    }
  }
}
