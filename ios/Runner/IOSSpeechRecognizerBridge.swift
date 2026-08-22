import AVFoundation
import Darwin
import Flutter
import Speech

enum IOSNativeSpeechEngineKind: String, Sendable {
  case speechAnalyzer = "speech_analyzer"
  case sfSpeechRecognizer = "sf_speech_recognizer"
}

struct IOSNativeSpeechEngineSelector {
  static func select(
    isIOS26OrNewer: Bool,
    speechAnalyzerSupported: Bool,
    sfOnDeviceSupported: Bool
  ) -> IOSNativeSpeechEngineKind? {
    if isIOS26OrNewer, speechAnalyzerSupported {
      return .speechAnalyzer
    }
    if sfOnDeviceSupported {
      return .sfSpeechRecognizer
    }
    return nil
  }
}

struct IOSNativeSpeechTaskHintSelector {
  static func select(commandMode: Bool) -> SFSpeechRecognitionTaskHint {
    // MAIN accepts normal navigation phrases, so both modes use dictation.
    // `.confirmation` can terminate Vietnamese recognition immediately.
    .dictation
  }
}

/// Native, on-device-first speech recognition for iOS.
///
/// iOS 26 uses SpeechAnalyzer when the Vietnamese model is supported. Older
/// devices use SFSpeechRecognizer only when it explicitly reports on-device
/// support. The Dart layer owns the Cloudflare/Batch fallback; this bridge never
/// silently sends speech to Apple's recognition servers.
final class IOSSpeechRecognizerBridge: NSObject, FlutterStreamHandler {
  private static let locale = Locale(identifier: "vi-VN")

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let audioSession = AVAudioSession.sharedInstance()
  private let audioEngine = AVAudioEngine()

  private var eventSink: FlutterEventSink?
  private var recognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var analyzerSession: AnyObject?
  private var recordingFile: AVAudioFile?
  private var recordingURL: URL?
  private var inputTapInstalled = false
  private var activeEngine: IOSNativeSpeechEngineKind?
  private var active = false
  private var stopping = false
  private var cancelled = false
  private var disposed = false
  private var beganSpeech = false
  private var generation = 0
  private var startRequestGeneration = 0
  private var preparedEngine: IOSNativeSpeechEngineKind?
  private var enginePreparationTask: Task<IOSNativeSpeechEngineKind?, Never>?
  private var latestText = ""
  private var latestAlternatives: [String] = []
  private var latestConfidence = -1.0
  private var startRequestedAt: Date?
  private var readyAt: Date?
  private var firstPartialAt: Date?
  private var finalAt: Date?

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: "ailingo_speech", binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: "ailingo_speech/events", binaryMessenger: messenger)
    super.init()
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    eventChannel.setStreamHandler(self)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !disposed else {
      result(FlutterError(code: "SPEECH_DISPOSED", message: "Apple Speech bridge đã đóng.", details: nil))
      return
    }
    switch call.method {
    case "speech.isAvailable":
      Task { @MainActor [weak self] in
        guard let self else { return }
        result(await self.selectedEngineWithoutInstallingAssets() != nil)
      }
    case "speech.supportsAudioSource":
      // Live native recognition captures its own private fallback WAV. It does
      // not accept a Dart-provided audio source like Android 13+.
      result(false)
    case "speech.prepare":
      prepare(result)
    case "speech.start":
      let arguments = call.arguments as? [String: Any]
      let commandMode = arguments?["commandMode"] as? Bool ?? false
      start(commandMode: commandMode, result: result)
    case "speech.stop":
      stop(result)
    case "speech.cancel":
      startRequestGeneration += 1
      cancelCurrent(deleteRecording: true)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func prepare(_ result: @escaping FlutterResult) {
    ensureSpeechAuthorization { [weak self] authorization in
      guard let self else { return }
      guard authorization == .authorized else {
        result(
          FlutterError(
            code: "SPEECH_PERMISSION_DENIED",
            message: "HOMI cần quyền Nhận dạng giọng nói để dùng Apple Speech.",
            details: nil
          )
        )
        return
      }
      Task { @MainActor [weak self] in
        guard let self else { return }
        result(await self.prepareBestEngine() != nil)
      }
    }
  }

  private func start(commandMode: Bool, result: @escaping FlutterResult) {
    startRequestGeneration += 1
    let requestGeneration = startRequestGeneration
    if active {
      cancelCurrent(deleteRecording: true)
    }
    ensureSpeechAuthorization { [weak self] authorization in
      guard let self else { return }
      guard self.isCurrentStartRequest(requestGeneration) else {
        self.completeCancelledStart(result)
        return
      }
      guard authorization == .authorized else {
        result(
          FlutterError(
            code: "SPEECH_PERMISSION_DENIED",
            message: "Quyền Nhận dạng giọng nói đã bị từ chối.",
            details: nil
          )
        )
        return
      }
      self.ensureMicrophonePermission { [weak self] granted in
        guard let self else { return }
        guard self.isCurrentStartRequest(requestGeneration) else {
          self.completeCancelledStart(result)
          return
        }
        guard granted else {
          result(
            FlutterError(
              code: "MICROPHONE_PERMISSION_DENIED",
              message: "Ứng dụng cần quyền micro để nghe con nói.",
              details: nil
            )
          )
          return
        }
        Task { @MainActor [weak self] in
          guard let self else { return }
          do {
            guard let engine = await self.prepareBestEngine() else {
              throw IOSSpeechBridgeError.onDeviceUnavailable
            }
            guard self.isCurrentStartRequest(requestGeneration) else {
              throw IOSSpeechBridgeError.startCancelled
            }
            try await self.beginRecognition(
              engine: engine,
              commandMode: commandMode,
              startRequestGeneration: requestGeneration
            )
            guard self.isCurrentStartRequest(requestGeneration) else {
              throw IOSSpeechBridgeError.startCancelled
            }
            result(true)
          } catch {
            guard self.isCurrentStartRequest(requestGeneration) else {
              self.completeCancelledStart(result)
              return
            }
            self.cancelCurrent(deleteRecording: true)
            result(
              FlutterError(
                code: "IOS_NATIVE_SPEECH_UNAVAILABLE",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        }
      }
    }
  }

  private func stop(_ result: @escaping FlutterResult) {
    guard active else {
      result(FlutterError(code: "SPEECH_NOT_ACTIVE", message: "Chưa có lượt Apple Speech đang chạy.", details: nil))
      return
    }
    stopping = true
    stopAudioCapture()
    emit(type: "speech.end")

    if #available(iOS 26.0, *),
      activeEngine == .speechAnalyzer,
      let session = analyzerSession as? IOSSpeechAnalyzerSession
    {
      Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          let transcript = try await session.stop()
          self.finishSuccessfully(
            text: transcript.text,
            alternatives: transcript.alternatives,
            confidence: -1
          )
          result(true)
        } catch {
          self.finishWithError(code: "SPEECH_ANALYZER_FAILED", error: error)
          result(true)
        }
      }
      return
    }

    recognitionRequest?.endAudio()
    recognitionTask?.finish()
    let stopGeneration = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(650)) { [weak self] in
      guard let self, self.active, self.generation == stopGeneration else { return }
      if self.latestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        self.finishWithError(code: "NO_SPEECH", error: IOSSpeechBridgeError.noSpeech)
      } else {
        self.finishSuccessfully(
          text: self.latestText,
          alternatives: self.latestAlternatives,
          confidence: self.latestConfidence
        )
      }
    }
    result(true)
  }

  private func beginRecognition(
    engine: IOSNativeSpeechEngineKind,
    commandMode: Bool,
    startRequestGeneration: Int
  ) async throws {
    guard isCurrentStartRequest(startRequestGeneration) else {
      throw IOSSpeechBridgeError.startCancelled
    }
    cancelCurrent(deleteRecording: true)
    guard isCurrentStartRequest(startRequestGeneration) else {
      throw IOSSpeechBridgeError.startCancelled
    }
    generation += 1
    let currentGeneration = generation
    activeEngine = engine
    active = true
    stopping = false
    cancelled = false
    beganSpeech = false
    latestText = ""
    latestAlternatives = []
    latestConfidence = -1
    startRequestedAt = Date()
    readyAt = nil
    firstPartialAt = nil
    finalAt = nil

    try configureAudioSession()
    try createPrivateFallbackRecording()

    if engine == .speechAnalyzer {
      guard #available(iOS 26.0, *) else {
        throw IOSSpeechBridgeError.onDeviceUnavailable
      }
      let session = try await IOSSpeechAnalyzerSession(locale: Self.locale)
      guard isCurrentStartRequest(startRequestGeneration) else {
        await session.cancel()
        throw IOSSpeechBridgeError.startCancelled
      }
      session.onUpdate = { [weak self] transcript in
        DispatchQueue.main.async {
          guard let self, self.active, self.generation == currentGeneration else { return }
          self.handleTranscriptUpdate(
            text: transcript.text,
            alternatives: transcript.alternatives,
            confidence: -1,
            isFinal: false
          )
        }
      }
      session.onFailure = { [weak self] error in
        DispatchQueue.main.async {
          guard let self, self.active, self.generation == currentGeneration else { return }
          self.finishWithError(code: "SPEECH_ANALYZER_FAILED", error: error)
        }
      }
      analyzerSession = session
    } else {
      try startLegacyRecognizer(commandMode: commandMode, generation: currentGeneration)
    }

    guard isCurrentStartRequest(startRequestGeneration) else {
      throw IOSSpeechBridgeError.startCancelled
    }
    try installAudioTap(generation: currentGeneration)
    audioEngine.prepare()
    guard isCurrentStartRequest(startRequestGeneration) else {
      throw IOSSpeechBridgeError.startCancelled
    }
    try audioEngine.start()
    readyAt = Date()
    emit(type: "speech.ready")
  }

  private func startLegacyRecognizer(commandMode: Bool, generation: Int) throws {
    guard let recognizer = onDeviceLegacyRecognizer() else {
      throw IOSSpeechBridgeError.onDeviceUnavailable
    }
    self.recognizer = recognizer
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true
    request.taskHint = IOSNativeSpeechTaskHintSelector.select(
      commandMode: commandMode
    )
    recognitionRequest = request
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] recognitionResult, error in
      DispatchQueue.main.async {
        guard let self, self.active, self.generation == generation, !self.cancelled else { return }
        if let recognitionResult {
          let best = recognitionResult.bestTranscription
          let alternatives = recognitionResult.transcriptions.map(\.formattedString)
          let confidence = best.segments.isEmpty
            ? -1
            : Double(best.segments.map(\.confidence).reduce(0, +)) / Double(best.segments.count)
          self.handleTranscriptUpdate(
            text: best.formattedString,
            alternatives: alternatives,
            confidence: confidence,
            isFinal: recognitionResult.isFinal
          )
          if recognitionResult.isFinal {
            self.finishSuccessfully(
              text: best.formattedString,
              alternatives: alternatives,
              confidence: confidence
            )
            return
          }
        }
        if let error, self.active {
          if self.stopping && !self.latestText.isEmpty {
            self.finishSuccessfully(
              text: self.latestText,
              alternatives: self.latestAlternatives,
              confidence: self.latestConfidence
            )
          } else {
            self.finishWithError(code: "SF_SPEECH_RECOGNIZER_FAILED", error: error)
          }
        }
      }
    }
  }

  private func installAudioTap(generation: Int) throws {
    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw IOSSpeechBridgeError.audioInputUnavailable
    }
    if inputTapInstalled {
      inputNode.removeTap(onBus: 0)
      inputTapInstalled = false
    }
    inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
      guard let self, self.active, self.generation == generation else { return }
      do {
        try self.recordingFile?.write(from: buffer)
        if #available(iOS 26.0, *),
          self.activeEngine == .speechAnalyzer,
          let analyzer = self.analyzerSession as? IOSSpeechAnalyzerSession
        {
          // AVAudioConverter may retain its input. AVAudioEngine owns and reuses
          // tap buffers, so pass a deep copy to avoid later corruption.
          try analyzer.append(self.copyForSpeechAnalyzer(buffer))
        } else {
          self.recognitionRequest?.append(buffer)
        }
        self.emitRms(buffer)
      } catch {
        DispatchQueue.main.async {
          guard self.active, self.generation == generation else { return }
          self.finishWithError(code: "AUDIO_STREAM_FAILED", error: error)
        }
      }
    }
    inputTapInstalled = true
  }

  private func copyForSpeechAnalyzer(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    guard let copy = AVAudioPCMBuffer(
      pcmFormat: source.format,
      frameCapacity: source.frameLength
    ) else {
      throw IOSSpeechBridgeError.audioBufferCopyFailed
    }
    copy.frameLength = source.frameLength

    let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
    let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    guard sourceBuffers.count == destinationBuffers.count else {
      throw IOSSpeechBridgeError.audioBufferCopyFailed
    }
    for index in 0..<sourceBuffers.count {
      let sourceBuffer = sourceBuffers[index]
      let destinationBuffer = destinationBuffers[index]
      guard let sourceData = sourceBuffer.mData,
        let destinationData = destinationBuffer.mData
      else {
        throw IOSSpeechBridgeError.audioBufferCopyFailed
      }
      memcpy(destinationData, sourceData, Int(sourceBuffer.mDataByteSize))
    }
    return copy
  }

  private func handleTranscriptUpdate(
    text: String,
    alternatives: [String],
    confidence: Double,
    isFinal: Bool
  ) {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    latestText = normalized
    latestAlternatives = alternatives.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    latestConfidence = confidence
    firstPartialAt = firstPartialAt ?? Date()
    emit(
      type: isFinal ? "speech.final" : "speech.partial",
      values: [
        "text": normalized,
        "alternatives": latestAlternatives,
        "confidence": confidence,
      ]
    )
  }

  private func finishSuccessfully(text: String, alternatives: [String], confidence: Double) {
    guard active else { return }
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      finishWithError(code: "NO_SPEECH", error: IOSSpeechBridgeError.noSpeech)
      return
    }
    finalAt = Date()
    stopAudioCapture()
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest = nil
    analyzerSession = nil
    active = false
    stopping = false
    discardPrivateRecording()
    emit(
      type: "speech.final",
      values: [
        "text": normalized,
        "alternatives": alternatives.isEmpty ? [normalized] : alternatives,
        "confidence": confidence,
      ]
    )
  }

  private func finishWithError(code: String, error: Error) {
    guard active else { return }
    finalAt = Date()
    stopAudioCapture()
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest = nil
    if #available(iOS 26.0, *), let analyzer = analyzerSession as? IOSSpeechAnalyzerSession {
      Task { await analyzer.cancel() }
    }
    analyzerSession = nil
    active = false
    stopping = false
    closePrivateRecording()
    var values: [String: Any] = [
      "code": code,
      "message": error.localizedDescription,
    ]
    if let metadata = fallbackRecordingMetadata() {
      values.merge(metadata) { _, new in new }
    }
    emit(type: "speech.error", values: values)
  }

  private func emitRms(_ buffer: AVAudioPCMBuffer) {
    guard let channel = buffer.floatChannelData?.pointee else { return }
    let count = Int(buffer.frameLength)
    guard count > 0 else { return }
    var sum = 0.0
    for index in 0..<count {
      let value = Double(channel[index])
      sum += value * value
    }
    let rms = sqrt(sum / Double(count))
    let db = max(-60, 20 * log10(max(rms, 0.000_001)))
    if !beganSpeech, db > -42 {
      beganSpeech = true
      emit(type: "speech.begin")
    }
    emit(type: "speech.rms", values: ["rmsDb": db])
  }

  private func configureAudioSession() throws {
    try audioSession.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
    )
    try audioSession.setActive(true)
  }

  private func createPrivateFallbackRecording() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("homi_ios_speech_\(UUID().uuidString.lowercased()).wav")
    let format = audioEngine.inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw IOSSpeechBridgeError.audioInputUnavailable
    }
    recordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
    recordingURL = url
  }

  private func stopAudioCapture() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    if inputTapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      inputTapInstalled = false
    }
    recordingFile = nil
  }

  private func closePrivateRecording() {
    recordingFile = nil
  }

  private func discardPrivateRecording() {
    closePrivateRecording()
    if let recordingURL {
      try? FileManager.default.removeItem(at: recordingURL)
    }
    recordingURL = nil
  }

  private func fallbackRecordingMetadata() -> [String: Any]? {
    guard let url = recordingURL,
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let byteLength = (attributes[.size] as? NSNumber)?.intValue,
      byteLength > 44
    else {
      return nil
    }
    return [
      "audioPath": url.path,
      "audioMimeType": "audio/wav",
      "audioByteLength": byteLength,
      "audioSampleRate": Int(audioSession.sampleRate.rounded()),
      "isBluetoothInput": isBluetoothInput(),
    ]
  }

  private func cancelCurrent(deleteRecording: Bool) {
    generation += 1
    cancelled = true
    stopAudioCapture()
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest = nil
    if #available(iOS 26.0, *), let analyzer = analyzerSession as? IOSSpeechAnalyzerSession {
      Task { await analyzer.cancel() }
    }
    analyzerSession = nil
    active = false
    stopping = false
    if deleteRecording {
      discardPrivateRecording()
    } else {
      closePrivateRecording()
    }
  }

  private func isCurrentStartRequest(_ requestGeneration: Int) -> Bool {
    !disposed && requestGeneration == startRequestGeneration
  }

  private func completeCancelledStart(_ result: @escaping FlutterResult) {
    result(
      FlutterError(
        code: "SPEECH_START_CANCELLED",
        message: IOSSpeechBridgeError.startCancelled.localizedDescription,
        details: nil
      )
    )
  }

  @MainActor
  private func selectedEngineWithoutInstallingAssets() async -> IOSNativeSpeechEngineKind? {
    let legacyAvailable = onDeviceLegacyRecognizer() != nil
    if #available(iOS 26.0, *) {
      return IOSNativeSpeechEngineSelector.select(
        isIOS26OrNewer: true,
        speechAnalyzerSupported: await IOSSpeechAnalyzerSession.supports(locale: Self.locale),
        sfOnDeviceSupported: legacyAvailable
      )
    }
    return IOSNativeSpeechEngineSelector.select(
      isIOS26OrNewer: false,
      speechAnalyzerSupported: false,
      sfOnDeviceSupported: legacyAvailable
    )
  }

  @MainActor
  private func prepareBestEngine() async -> IOSNativeSpeechEngineKind? {
    if let preparedEngine {
      return preparedEngine
    }
    if let enginePreparationTask {
      return await enginePreparationTask.value
    }
    let preparationTask = Task<IOSNativeSpeechEngineKind?, Never> { @MainActor [weak self] in
      guard let self else { return nil }
      return await self.loadBestEngine()
    }
    enginePreparationTask = preparationTask
    let engine = await preparationTask.value
    enginePreparationTask = nil
    if let engine {
      preparedEngine = engine
    }
    return engine
  }

  @MainActor
  private func loadBestEngine() async -> IOSNativeSpeechEngineKind? {
    if #available(iOS 26.0, *) {
      let analyzerSupported = await IOSSpeechAnalyzerSession.supports(locale: Self.locale)
      if analyzerSupported {
        do {
          try await IOSSpeechAnalyzerSession.installAssets(locale: Self.locale)
          return .speechAnalyzer
        } catch {
          // Continue to the strictly on-device legacy recognizer. If it is not
          // available, Dart starts Cloudflare/Batch instead.
        }
      }
    }
    return onDeviceLegacyRecognizer() == nil ? nil : .sfSpeechRecognizer
  }

  private func onDeviceLegacyRecognizer() -> SFSpeechRecognizer? {
    let requested = Self.locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    let supported = SFSpeechRecognizer.supportedLocales().contains { locale in
      locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased() == requested
    }
    guard supported,
      let recognizer = SFSpeechRecognizer(locale: Self.locale),
      recognizer.supportsOnDeviceRecognition
    else {
      return nil
    }
    return recognizer
  }

  private func ensureSpeechAuthorization(
    completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void
  ) {
    let status = SFSpeechRecognizer.authorizationStatus()
    if status != .notDetermined {
      completion(status)
      return
    }
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async { completion(status) }
    }
  }

  private func ensureMicrophonePermission(completion: @escaping (Bool) -> Void) {
    switch audioSession.recordPermission {
    case .granted:
      completion(true)
    case .denied:
      completion(false)
    case .undetermined:
      audioSession.requestRecordPermission { granted in
        DispatchQueue.main.async { completion(granted) }
      }
    @unknown default:
      completion(false)
    }
  }

  private func metadata() -> [String: Any] {
    let now = Date()
    var values: [String: Any] = [
      "engine": activeEngine?.rawValue ?? "unknown",
      "locale": Self.locale.identifier,
      "onDevice": true,
      "audioRoute": routeDescription(),
      "isBluetoothInput": isBluetoothInput(),
    ]
    if let startRequestedAt, let readyAt {
      values["listeningReadyMs"] = max(0, Int(readyAt.timeIntervalSince(startRequestedAt) * 1_000))
    }
    if let startRequestedAt, let firstPartialAt {
      values["firstPartialMs"] = max(0, Int(firstPartialAt.timeIntervalSince(startRequestedAt) * 1_000))
    }
    if let startRequestedAt, let finalAt {
      values["finalTranscriptMs"] = max(0, Int(finalAt.timeIntervalSince(startRequestedAt) * 1_000))
    }
    values["eventEpochMs"] = Int(now.timeIntervalSince1970 * 1_000)
    return values
  }

  private func routeDescription() -> String {
    let inputs = audioSession.currentRoute.inputs.map { "\($0.portType.rawValue):\($0.portName)" }
    let outputs = audioSession.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
    return "in=[\(inputs.joined(separator: ", "))] out=[\(outputs.joined(separator: ", "))]"
  }

  private func isBluetoothInput() -> Bool {
    audioSession.currentRoute.inputs.contains {
      $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
    }
  }

  private func emit(type: String, values: [String: Any] = [:]) {
    guard !disposed else { return }
    var payload = metadata()
    payload["type"] = type
    payload.merge(values) { _, new in new }
    eventSink?(payload)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func dispose() {
    guard !disposed else { return }
    startRequestGeneration += 1
    cancelCurrent(deleteRecording: true)
    disposed = true
    eventSink = nil
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
  }
}

private struct IOSAnalyzerTranscript {
  let text: String
  let alternatives: [String]
}

@available(iOS 26.0, *)
private final class IOSSpeechAnalyzerSession {
  static func supports(locale: Locale) async -> Bool {
    guard SpeechTranscriber.isAvailable else { return false }
    let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    return supportedLocale != nil
  }

  static func installAssets(locale: Locale) async throws {
    guard SpeechTranscriber.isAvailable,
      let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    else {
      throw IOSSpeechBridgeError.onDeviceUnavailable
    }
    let transcriber = SpeechTranscriber(
      locale: supportedLocale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults, .fastResults, .alternativeTranscriptions],
      attributeOptions: []
    )
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }
  }

  var onUpdate: ((IOSAnalyzerTranscript) -> Void)?
  var onFailure: ((Error) -> Void)?

  private let transcriber: SpeechTranscriber
  private let analyzer: SpeechAnalyzer
  private let analyzerFormat: AVAudioFormat
  private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
  private var audioConverter: AVAudioConverter?
  private var analysisTask: Task<Void, Error>?
  private var resultTask: Task<Void, Never>?
  private var finalizedSegments: [String] = []
  private var volatileText = ""
  private var latestAlternatives: [String] = []

  init(locale: Locale) async throws {
    guard SpeechTranscriber.isAvailable,
      let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    else {
      throw IOSSpeechBridgeError.onDeviceUnavailable
    }
    transcriber = SpeechTranscriber(
      locale: supportedLocale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults, .fastResults, .alternativeTranscriptions],
      attributeOptions: []
    )
    analyzer = SpeechAnalyzer(modules: [transcriber])
    guard let compatibleFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: [transcriber]
    ) else {
      throw IOSSpeechBridgeError.onDeviceUnavailable
    }
    analyzerFormat = compatibleFormat
    let stream = AsyncStream<AnalyzerInput>.makeStream()
    inputContinuation = stream.continuation

    let analyzer = self.analyzer
    analysisTask = Task {
      let lastSample = try await analyzer.analyzeSequence(stream.stream)
      if let lastSample {
        try await analyzer.finalizeAndFinish(through: lastSample)
      } else {
        await analyzer.cancelAndFinishNow()
      }
    }
    let transcriber = self.transcriber
    resultTask = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          guard let self else { return }
          let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
          let alternatives = result.alternatives.map {
            String($0.characters).trimmingCharacters(in: .whitespacesAndNewlines)
          }.filter { !$0.isEmpty }
          if result.isFinal {
            if !text.isEmpty { self.finalizedSegments.append(text) }
            self.volatileText = ""
          } else {
            self.volatileText = text
          }
          self.latestAlternatives = alternatives
          self.onUpdate?(self.snapshot())
        }
      } catch is CancellationError {
        return
      } catch {
        self?.onFailure?(error)
      }
    }
  }

  func append(_ buffer: AVAudioPCMBuffer) throws {
    if let convertedBuffer = try convert(buffer) {
      inputContinuation.yield(AnalyzerInput(buffer: convertedBuffer))
    }
  }

  func stop() async throws -> IOSAnalyzerTranscript {
    for convertedBuffer in try flushAudioConverter() {
      inputContinuation.yield(AnalyzerInput(buffer: convertedBuffer))
    }
    inputContinuation.finish()
    try await analysisTask?.value
    await resultTask?.value
    return snapshot()
  }

  func cancel() async {
    inputContinuation.finish()
    analysisTask?.cancel()
    resultTask?.cancel()
    await analyzer.cancelAndFinishNow()
  }

  private func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
    let activeConverter = try makeOrReuseConverter(for: inputBuffer.format)
    let sampleRateRatio = analyzerFormat.sampleRate / inputBuffer.format.sampleRate
    let estimatedFrames = ceil(Double(inputBuffer.frameLength) * sampleRateRatio)
    let outputCapacity = max(AVAudioFrameCount(estimatedFrames) + 64, 1)
    guard let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: analyzerFormat,
      frameCapacity: outputCapacity
    ) else {
      throw IOSSpeechBridgeError.audioConversionUnavailable
    }

    var suppliedInput = false
    var conversionError: NSError?
    let status = activeConverter.convert(to: outputBuffer, error: &conversionError) {
      _, inputStatus in
      guard !suppliedInput else {
        inputStatus.pointee = .noDataNow
        return nil
      }
      suppliedInput = true
      inputStatus.pointee = .haveData
      return inputBuffer
    }
    if status == .error {
      if let conversionError { throw conversionError }
      throw IOSSpeechBridgeError.audioConversionFailed
    }
    return outputBuffer.frameLength == 0 ? nil : outputBuffer
  }

  private func makeOrReuseConverter(for inputFormat: AVAudioFormat) throws -> AVAudioConverter {
    if let audioConverter, audioConverter.inputFormat.isEqual(inputFormat) {
      return audioConverter
    }
    guard let replacement = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
      throw IOSSpeechBridgeError.audioConversionUnavailable
    }
    audioConverter = replacement
    return replacement
  }

  private func flushAudioConverter() throws -> [AVAudioPCMBuffer] {
    guard let audioConverter else { return [] }
    var convertedBuffers: [AVAudioPCMBuffer] = []
    let sampleRateRatio = analyzerFormat.sampleRate / audioConverter.inputFormat.sampleRate
    let outputCapacity = max(AVAudioFrameCount(ceil(1_024.0 * sampleRateRatio)) + 64, 1_024)

    // A sample-rate converter may retain a small tail. Signal end-of-stream and
    // drain it before terminating SpeechAnalyzer's AsyncStream.
    for _ in 0..<8 {
      guard let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: analyzerFormat,
        frameCapacity: outputCapacity
      ) else {
        throw IOSSpeechBridgeError.audioConversionUnavailable
      }
      var conversionError: NSError?
      let status = audioConverter.convert(to: outputBuffer, error: &conversionError) {
        _, inputStatus in
        inputStatus.pointee = .endOfStream
        return nil
      }
      if status == .error {
        if let conversionError { throw conversionError }
        throw IOSSpeechBridgeError.audioConversionFailed
      }
      if outputBuffer.frameLength > 0 {
        convertedBuffers.append(outputBuffer)
      }
      if status == .endOfStream || (status == .inputRanDry && outputBuffer.frameLength == 0) {
        break
      }
    }
    self.audioConverter = nil
    return convertedBuffers
  }

  private func snapshot() -> IOSAnalyzerTranscript {
    let components = finalizedSegments + (volatileText.isEmpty ? [] : [volatileText])
    let text = components.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    let alternatives = latestAlternatives.isEmpty ? (text.isEmpty ? [] : [text]) : latestAlternatives
    return IOSAnalyzerTranscript(text: text, alternatives: alternatives)
  }
}

private enum IOSSpeechBridgeError: LocalizedError {
  case onDeviceUnavailable
  case audioInputUnavailable
  case audioBufferCopyFailed
  case audioConversionUnavailable
  case audioConversionFailed
  case noSpeech
  case startCancelled

  var errorDescription: String? {
    switch self {
    case .onDeviceUnavailable:
      return "Thiết bị chưa hỗ trợ nhận dạng tiếng Việt on-device; HOMI sẽ dùng Cloudflare/Batch dự phòng."
    case .audioInputUnavailable:
      return "iOS chưa mở được micro iPhone hoặc H20 HFP."
    case .audioBufferCopyFailed:
      return "iOS chưa sao chép được luồng micro cho Apple Speech."
    case .audioConversionUnavailable:
      return "iOS chưa tạo được bộ chuyển đổi âm thanh cho Apple Speech."
    case .audioConversionFailed:
      return "iOS chưa chuyển đổi được âm thanh cho Apple Speech."
    case .noSpeech:
      return "Mình chưa nghe rõ. Con thử nói lại gần micro hơn nhé."
    case .startCancelled:
      return "Lượt mở Apple Speech đã được thay thế hoặc hủy."
    }
  }
}
