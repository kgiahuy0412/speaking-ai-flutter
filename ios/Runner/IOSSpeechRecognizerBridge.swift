import AVFoundation
import Darwin
import Flutter
import Speech

enum IOSNativeSpeechEngineKind: String, Sendable {
  case speechAnalyzer = "speech_analyzer"
  case sfSpeechRecognizer = "sf_speech_recognizer"
}

enum IOSNativeSpeechAudioSource: String, Sendable {
  case builtInMic
  case hfp

  static func fromChannelValue(_ value: Any?) -> IOSNativeSpeechAudioSource {
    guard let rawValue = value as? String,
      let source = IOSNativeSpeechAudioSource(rawValue: rawValue)
    else {
      return .builtInMic
    }
    return source
  }
}

struct IOSNativeSpeechAudioRoutePolicy {
  static func categoryOptions(
    for source: IOSNativeSpeechAudioSource
  ) -> AVAudioSession.CategoryOptions {
    switch source {
    case .builtInMic:
      return [.defaultToSpeaker]
    case .hfp:
      // A2DP is output-only and can prevent the bidirectional HFP profile from
      // becoming the active recording route.
      return IOSHfpRoutePolicy.categoryOptions
    }
  }

  static func accepts(
    portType: AVAudioSession.Port,
    for source: IOSNativeSpeechAudioSource
  ) -> Bool {
    switch source {
    case .builtInMic:
      return portType == .builtInMic
    case .hfp:
      return portType == .bluetoothHFP
    }
  }
}

/// Reads a conventional dBFS value from the PCM formats commonly delivered by
/// AVAudioEngine. HFP devices are not guaranteed to use Float32, so limiting
/// voice activity detection to `floatChannelData` can silently discard a real
/// H20 microphone stream even while the route and SCO state are correct.
struct IOSAudioBufferLevel {
  static func dbfs(_ buffer: AVAudioPCMBuffer) -> Double? {
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard frameCount > 0, channelCount > 0 else { return nil }

    let samplesPerChannel = buffer.format.isInterleaved
      ? frameCount * channelCount
      : frameCount
    let pointerCount = buffer.format.isInterleaved ? 1 : channelCount
    var squaredSum = 0.0
    var sampleCount = 0

    switch buffer.format.commonFormat {
    case .pcmFormatFloat32:
      guard let channels = buffer.floatChannelData else { return nil }
      for channelIndex in 0..<pointerCount {
        let channel = channels[channelIndex]
        for sampleIndex in 0..<samplesPerChannel {
          let value = Double(channel[sampleIndex])
          squaredSum += value * value
        }
        sampleCount += samplesPerChannel
      }
    case .pcmFormatInt16:
      guard let channels = buffer.int16ChannelData else { return nil }
      for channelIndex in 0..<pointerCount {
        let channel = channels[channelIndex]
        for sampleIndex in 0..<samplesPerChannel {
          let value = Double(channel[sampleIndex]) / 32_768.0
          squaredSum += value * value
        }
        sampleCount += samplesPerChannel
      }
    case .pcmFormatInt32:
      guard let channels = buffer.int32ChannelData else { return nil }
      for channelIndex in 0..<pointerCount {
        let channel = channels[channelIndex]
        for sampleIndex in 0..<samplesPerChannel {
          let value = Double(channel[sampleIndex]) / 2_147_483_648.0
          squaredSum += value * value
        }
        sampleCount += samplesPerChannel
      }
    default:
      return nil
    }

    guard sampleCount > 0 else { return nil }
    let rms = sqrt(squaredSum / Double(sampleCount))
    return max(-60, min(0, 20 * log10(max(rms, 0.000_001))))
  }
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

  static func selectForRecognition(
    preparedEngine: IOSNativeSpeechEngineKind,
    commandMode _: Bool,
    sfOnDeviceSupported _: Bool
  ) -> IOSNativeSpeechEngineKind {
    // `prepareBestEngine` has already selected the best on-device engine for
    // this OS/locale. MAIN must not replace SpeechAnalyzer with the legacy
    // recognizer: on iOS 26 that recognizer can fail immediately for vi-VN,
    // which presents as "ready cue, then the listening UI disappears".
    return preparedEngine
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
/// support. A turn stays on the engine selected before it starts and errors are
/// returned directly; speech is never uploaded to a Batch fallback.
final class IOSSpeechRecognizerBridge: NSObject, FlutterStreamHandler {
  private static let defaultLocale = Locale(identifier: "vi-VN")

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let audioSessionCoordinator: IOSAudioSessionCoordinator
  private var audioSession: AVAudioSession { audioSessionCoordinator.session }
  private let audioEngine = AVAudioEngine()

  private var eventSink: FlutterEventSink?
  private var recognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var analyzerSession: AnyObject?
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
  private var preparedLocaleIdentifier: String?
  private var enginePreparationTask: Task<IOSNativeSpeechEngineKind?, Never>?
  private var enginePreparationLocaleIdentifier: String?
  private var latestText = ""
  private var latestAlternatives: [String] = []
  private var latestConfidence = -1.0
  private var startRequestedAt: Date?
  private var readyAt: Date?
  private var firstPartialAt: Date?
  private var finalAt: Date?
  private var requestedAudioSource = IOSNativeSpeechAudioSource.builtInMic
  private var requestedLocale = Locale(identifier: "vi-VN")
  private var lastDiagnosticStage = "idle"
  private var firstAnalyzerInputGeneration: Int?

  init(
    messenger: FlutterBinaryMessenger,
    audioSessionCoordinator: IOSAudioSessionCoordinator
  ) {
    self.audioSessionCoordinator = audioSessionCoordinator
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
        result(
          await self.selectedEngineWithoutInstallingAssets(
            locale: Self.defaultLocale
          ) != nil
        )
      }
    case "speech.supportsAudioSource":
      // Live native recognition owns one AVAudioEngine pipeline and does not
      // accept or produce recorded-audio fallback files.
      result(false)
    case "speech.prepare":
      prepare(result)
    case "speech.start":
      let arguments = call.arguments as? [String: Any]
      let commandMode = arguments?["commandMode"] as? Bool ?? false
      let audioSource = IOSNativeSpeechAudioSource.fromChannelValue(
        arguments?["audioSource"]
      )
      let locale = Self.locale(from: arguments?["locale"])
      start(
        commandMode: commandMode,
        audioSource: audioSource,
        locale: locale
      )
      // A MethodChannel reply acknowledges that the start request was accepted;
      // readiness and failures are delivered exclusively through speech.ready /
      // speech.error. Holding FlutterResult until AVAudioEngine is ready allows
      // an Apple async operation to poison every later MAIN press when cancelled.
      result(true)
    case "speech.stop":
      stop(result)
    case "speech.cancel":
      startRequestGeneration += 1
      audioSessionCoordinator.trace(
        stage: "speech.cancel",
        caller: "IOSSpeechRecognizerBridge.channel"
      )
      cancelCurrent(
        deleteRecording: true,
        caller: "IOSSpeechRecognizerBridge.channel"
      )
      audioSessionCoordinator.endMainTurn(
        reason: "speech_cancelled",
        caller: "IOSSpeechRecognizerBridge.channel"
      )
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
        result(await self.prepareBestEngine(locale: Self.defaultLocale) != nil)
      }
    }
  }

  private func start(
    commandMode: Bool,
    audioSource: IOSNativeSpeechAudioSource,
    locale: Locale
  ) {
    startRequestGeneration += 1
    let requestGeneration = startRequestGeneration
    requestedAudioSource = audioSource
    requestedLocale = locale
    startRequestedAt = Date()
    if active {
      cancelCurrent(
        deleteRecording: true,
        caller: "IOSSpeechRecognizerBridge.start.replaceActive"
      )
      audioSessionCoordinator.endMainTurn(
        reason: "speech_replaced",
        caller: "IOSSpeechRecognizerBridge.start"
      )
    }
    if commandMode {
      _ = audioSessionCoordinator.beginMainTurn(
        source: "IOSSpeechRecognizerBridge.speech.start"
      )
    }
    ensureSpeechAuthorization { [weak self] authorization in
      guard let self else { return }
      guard self.isCurrentStartRequest(requestGeneration) else {
        return
      }
      guard authorization == .authorized else {
        self.failStart(
          code: "SPEECH_PERMISSION_DENIED",
          message: "Quyền Nhận dạng giọng nói đã bị từ chối.",
          reason: "speech_permission_denied"
        )
        return
      }
      self.ensureMicrophonePermission { [weak self] granted in
        guard let self else { return }
        guard self.isCurrentStartRequest(requestGeneration) else {
          return
        }
        guard granted else {
          self.failStart(
            code: "MICROPHONE_PERMISSION_DENIED",
            message: "Ứng dụng cần quyền micro để nghe con nói.",
            reason: "microphone_permission_denied"
          )
          return
        }
        Task { @MainActor [weak self] in
          guard let self else { return }
          do {
            guard let engine = await self.prepareBestEngine(locale: locale) else {
              throw IOSSpeechBridgeError.onDeviceUnavailable
            }
            guard self.isCurrentStartRequest(requestGeneration) else {
              throw IOSSpeechBridgeError.startCancelled
            }
            try await self.beginRecognition(
              engine: engine,
              commandMode: commandMode,
              audioSource: audioSource,
              locale: locale,
              startRequestGeneration: requestGeneration
            )
            guard self.isCurrentStartRequest(requestGeneration) else {
              throw IOSSpeechBridgeError.startCancelled
            }
          } catch {
            guard self.isCurrentStartRequest(requestGeneration) else {
              return
            }
            let errorCode = self.diagnosticCode(for: error)
            self.failStart(
              code: errorCode,
              message: error.localizedDescription,
              reason: errorCode
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
    audioSessionCoordinator.trace(
      stage: "speech.stop",
      caller: "IOSSpeechRecognizerBridge.channel"
    )
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
    audioSource: IOSNativeSpeechAudioSource,
    locale: Locale,
    startRequestGeneration: Int
  ) async throws {
    guard isCurrentStartRequest(startRequestGeneration) else {
      throw IOSSpeechBridgeError.startCancelled
    }
    cancelCurrent(
      deleteRecording: true,
      caller: "IOSSpeechRecognizerBridge.beginRecognition.cleanup"
    )
    guard isCurrentStartRequest(startRequestGeneration) else {
      throw IOSSpeechBridgeError.startCancelled
    }
    generation += 1
    let currentGeneration = generation
    let recognitionEngine = IOSNativeSpeechEngineSelector.selectForRecognition(
      preparedEngine: engine,
      commandMode: commandMode,
      sfOnDeviceSupported: onDeviceLegacyRecognizer(locale: locale) != nil
    )
    activeEngine = recognitionEngine
    active = true
    stopping = false
    cancelled = false
    beganSpeech = false
    latestText = ""
    latestAlternatives = []
    latestConfidence = -1
    startRequestedAt = startRequestedAt ?? Date()
    readyAt = nil
    firstPartialAt = nil
    finalAt = nil
    firstAnalyzerInputGeneration = nil
    emitStage("engine_selected", message: recognitionEngine.rawValue)

    try await configureAudioSession(audioSource: audioSource)

    if recognitionEngine == .speechAnalyzer {
      guard #available(iOS 26.0, *) else {
        throw IOSSpeechBridgeError.onDeviceUnavailable
      }
      let session = try await IOSSpeechAnalyzerSession(locale: locale)
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
          guard let self,
            self.active,
            self.generation == currentGeneration,
            self.activeEngine == .speechAnalyzer
          else { return }
          self.finishWithError(code: "SPEECH_ANALYZER_FAILED", error: error)
        }
      }
      analyzerSession = session
      session.start()
    } else {
      try startLegacyRecognizer(
        commandMode: commandMode,
        locale: locale,
        generation: currentGeneration
      )
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
    try await waitForRequestedAudioRoute(audioSource)
    emitStage("engine_started")
    try await waitForFirstAnalyzerInput(generation: currentGeneration)
    readyAt = Date()
    emitStage("speech.ready")
    emit(type: "speech.ready")
  }

  private func startLegacyRecognizer(
    commandMode: Bool,
    locale: Locale,
    generation: Int
  ) throws {
    guard let recognizer = onDeviceLegacyRecognizer(locale: locale) else {
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
        let analyzerInputCount: Int
        if #available(iOS 26.0, *),
          self.activeEngine == .speechAnalyzer,
          let analyzer = self.analyzerSession as? IOSSpeechAnalyzerSession
        {
          // The conversion/analysis pipeline may retain its input. AVAudioEngine
          // owns and reuses tap buffers, so pass a deep copy to avoid corruption.
          analyzerInputCount = try analyzer.append(self.copyForSpeechAnalyzer(buffer))
        } else {
          self.recognitionRequest?.append(buffer)
          analyzerInputCount = 1
        }
        self.processCapturedAudio(
          buffer,
          analyzerInputCount: analyzerInputCount,
          generation: generation
        )
      } catch {
        DispatchQueue.main.async {
          guard self.active, self.generation == generation else { return }
          self.audioSessionCoordinator.trace(
            stage: "SpeechAnalyzer.append_failed",
            caller: "IOSSpeechRecognizerBridge.audioTap",
            code: "AUDIO_STREAM_FAILED",
            message: error.localizedDescription
          )
          self.finishWithError(code: "AUDIO_STREAM_FAILED", error: error)
        }
      }
    }
    inputTapInstalled = true
    emitStage(
      "audio_tap_installed",
      message: "sampleRate=\(Int(format.sampleRate)) channels=\(format.channelCount) format=\(format.commonFormat.rawValue)"
    )
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
    audioSessionCoordinator.trace(
      stage: isFinal ? "speech.final_update" : "speech.partial",
      caller: "IOSSpeechRecognizerBridge.handleTranscriptUpdate",
      message: normalized
    )
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
    audioSessionCoordinator.trace(
      stage: "speech.final",
      caller: "IOSSpeechRecognizerBridge.finishSuccessfully",
      message: normalized
    )
    emit(
      type: "speech.final",
      values: [
        "text": normalized,
        "alternatives": alternatives.isEmpty ? [normalized] : alternatives,
        "confidence": confidence,
      ]
    )
    audioSessionCoordinator.endMainTurn(
      reason: "speech_final",
      caller: "IOSSpeechRecognizerBridge.finishSuccessfully"
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
    let values: [String: Any] = [
      "code": code,
      "message": error.localizedDescription,
    ]
    emitStage("error", code: code, message: error.localizedDescription)
    emit(type: "speech.error", values: values)
    audioSessionCoordinator.endMainTurn(
      reason: code,
      caller: "IOSSpeechRecognizerBridge.finishWithError"
    )
  }

  private func processCapturedAudio(
    _ buffer: AVAudioPCMBuffer,
    analyzerInputCount: Int,
    generation: Int
  ) {
    let frameLength = Int(buffer.frameLength)
    let sampleRate = Int(buffer.format.sampleRate.rounded())
    let db = IOSAudioBufferLevel.dbfs(buffer)
    let dbText = db.map { String(format: "%.1f", $0) } ?? "unknown"
    DispatchQueue.main.async { [weak self] in
      guard let self, self.active, self.generation == generation else { return }
      if analyzerInputCount > 0, self.firstAnalyzerInputGeneration != generation {
        self.firstAnalyzerInputGeneration = generation
        self.audioSessionCoordinator.trace(
          stage: "SpeechAnalyzer.append_succeeded",
          caller: "IOSSpeechRecognizerBridge.audioTap",
          message: "inputs=\(analyzerInputCount)"
        )
        self.emitStage(
          "first_audio_buffer",
          message: "frames=\(frameLength) sampleRate=\(sampleRate) analyzerInputs=\(analyzerInputCount) rmsDb=\(dbText)"
        )
      }
      guard let db else { return }
      if !self.beganSpeech, db > -42 {
        self.beganSpeech = true
        self.emitStage("speech.begin")
        self.emit(type: "speech.begin")
      }
      self.emit(type: "speech.rms", values: ["rmsDb": db])
    }
  }

  private func waitForFirstAnalyzerInput(
    generation: Int,
    attempts: Int = 40
  ) async throws {
    for attempt in 0..<attempts {
      guard active, self.generation == generation else {
        throw IOSSpeechBridgeError.startCancelled
      }
      if firstAnalyzerInputGeneration == generation {
        return
      }
      if attempt + 1 < attempts {
        try await Task<Never, Never>.sleep(nanoseconds: 50_000_000)
      }
    }
    throw IOSSpeechBridgeError.audioBufferTimeout
  }

  private func configureAudioSession(
    audioSource: IOSNativeSpeechAudioSource
  ) async throws {
    let target: IOSAudioInputTarget = audioSource == .hfp ? .hfp : .builtInMic
    do {
      try audioSessionCoordinator.prepareCapture(
        target: target,
        caller: "IOSSpeechRecognizerBridge.configureAudioSession"
      )
    } catch {
      switch audioSource {
      case .builtInMic:
        throw IOSSpeechBridgeError.builtInMicUnavailable
      case .hfp:
        throw IOSSpeechBridgeError.hfpInputUnavailable
      }
    }
    try await waitForRequestedAudioRoute(audioSource)
    emitStage("route_confirmed")
  }

  private func waitForRequestedAudioRoute(
    _ audioSource: IOSNativeSpeechAudioSource,
    attempts: Int = 20
  ) async throws {
    for attempt in 0..<attempts {
      let inputConfirmed = audioSession.currentRoute.inputs.contains(where: {
        IOSNativeSpeechAudioRoutePolicy.accepts(
          portType: $0.portType,
          for: audioSource
        )
      })
      let outputConfirmed = audioSource != .hfp
        || audioSession.currentRoute.outputs.contains(where: {
          IOSHfpRoutePolicy.isHfpOutput($0.portType)
        })
      if inputConfirmed && outputConfirmed {
        return
      }
      if attempt + 1 < attempts {
        try await Task<Never, Never>.sleep(nanoseconds: 100_000_000)
      }
    }
    throw IOSSpeechBridgeError.audioRouteMismatch(
      expected: audioSource.rawValue,
      actual: routeDescription()
    )
  }

  private func stopAudioCapture() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    if inputTapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      inputTapInstalled = false
    }
    audioEngine.reset()
  }

  private func cancelCurrent(deleteRecording _: Bool, caller: String) {
    audioSessionCoordinator.trace(stage: "speech.cancel_internal", caller: caller)
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
  }

  private func isCurrentStartRequest(_ requestGeneration: Int) -> Bool {
    !disposed && requestGeneration == startRequestGeneration
  }

  private func failStart(code: String, message: String, reason: String) {
    let failedStage = lastDiagnosticStage
    emitStage("error", code: code, message: message)
    emit(
      type: "speech.error",
      values: [
        "code": code,
        "message": message,
        "stage": failedStage,
        "audioSource": requestedAudioSource.rawValue,
        "audioRoute": routeDescription(),
      ]
    )
    cancelCurrent(
      deleteRecording: true,
      caller: "IOSSpeechRecognizerBridge.start.failed"
    )
    audioSessionCoordinator.endMainTurn(
      reason: reason,
      caller: "IOSSpeechRecognizerBridge.start"
    )
  }

  @MainActor
  private func selectedEngineWithoutInstallingAssets(
    locale: Locale
  ) async -> IOSNativeSpeechEngineKind? {
    let legacyAvailable = onDeviceLegacyRecognizer(locale: locale) != nil
    if #available(iOS 26.0, *) {
      return IOSNativeSpeechEngineSelector.select(
        isIOS26OrNewer: true,
        speechAnalyzerSupported: await IOSSpeechAnalyzerSession.supports(locale: locale),
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
  private func prepareBestEngine(locale: Locale) async -> IOSNativeSpeechEngineKind? {
    let localeIdentifier = Self.normalizedLocaleIdentifier(locale)
    if preparedLocaleIdentifier == localeIdentifier, let preparedEngine {
      return preparedEngine
    }
    if enginePreparationLocaleIdentifier == localeIdentifier,
      let enginePreparationTask
    {
      return await enginePreparationTask.value
    }
    enginePreparationTask?.cancel()
    let preparationTask = Task<IOSNativeSpeechEngineKind?, Never> { @MainActor [weak self] in
      guard let self else { return nil }
      return await self.loadBestEngine(locale: locale)
    }
    enginePreparationTask = preparationTask
    enginePreparationLocaleIdentifier = localeIdentifier
    let engine = await preparationTask.value
    let isCurrentPreparation = enginePreparationLocaleIdentifier == localeIdentifier
    if isCurrentPreparation {
      enginePreparationTask = nil
      enginePreparationLocaleIdentifier = nil
    }
    if isCurrentPreparation, let engine {
      preparedEngine = engine
      preparedLocaleIdentifier = localeIdentifier
    }
    return engine
  }

  @MainActor
  private func loadBestEngine(locale: Locale) async -> IOSNativeSpeechEngineKind? {
    if #available(iOS 26.0, *) {
      let analyzerSupported = await IOSSpeechAnalyzerSession.supports(locale: locale)
      if analyzerSupported {
        do {
          try await IOSSpeechAnalyzerSession.installAssets(locale: locale)
          return .speechAnalyzer
        } catch {
          // Continue to the strictly on-device legacy recognizer. This choice
          // happens before a turn starts; the active turn never switches engine.
        }
      }
    }
    return onDeviceLegacyRecognizer(locale: locale) == nil ? nil : .sfSpeechRecognizer
  }

  private func onDeviceLegacyRecognizer(locale: Locale) -> SFSpeechRecognizer? {
    let requested = Self.normalizedLocaleIdentifier(locale)
    let supported = SFSpeechRecognizer.supportedLocales().contains { locale in
      Self.normalizedLocaleIdentifier(locale) == requested
    }
    guard supported,
      let recognizer = SFSpeechRecognizer(locale: locale),
      recognizer.supportsOnDeviceRecognition
    else {
      return nil
    }
    return recognizer
  }

  private static func locale(from value: Any?) -> Locale {
    guard let identifier = value as? String else { return defaultLocale }
    let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? defaultLocale : Locale(identifier: trimmed)
  }

  private static func normalizedLocaleIdentifier(_ locale: Locale) -> String {
    locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
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
      "locale": requestedLocale.identifier,
      "onDevice": true,
      "audioRoute": routeDescription(),
      "isBluetoothInput": isBluetoothInput(),
      "audioSource": requestedAudioSource.rawValue,
      "diagnosticStage": lastDiagnosticStage,
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
    values.merge(audioSessionCoordinator.eventMetadata()) { _, new in new }
    return values
  }

  private func routeDescription() -> String {
    audioSessionCoordinator.routeDescription()
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

  private func emitStage(
    _ stage: String,
    code: String? = nil,
    message: String? = nil
  ) {
    lastDiagnosticStage = stage
    audioSessionCoordinator.trace(
      stage: stage,
      caller: "IOSSpeechRecognizerBridge",
      code: code,
      message: message,
      values: ["audioSource": requestedAudioSource.rawValue]
    )
  }

  private func diagnosticCode(for error: Error) -> String {
    guard let bridgeError = error as? IOSSpeechBridgeError else {
      return "IOS_NATIVE_SPEECH_UNAVAILABLE"
    }
    switch bridgeError {
    case .builtInMicUnavailable:
      return "BUILT_IN_MIC_UNAVAILABLE"
    case .hfpInputUnavailable:
      return "HFP_INPUT_UNAVAILABLE"
    case .audioRouteMismatch:
      return "AUDIO_ROUTE_MISMATCH"
    case .audioInputUnavailable:
      return "AUDIO_INPUT_UNAVAILABLE"
    case .onDeviceUnavailable:
      return "ON_DEVICE_SPEECH_UNAVAILABLE"
    case .startCancelled:
      return "SPEECH_START_CANCELLED"
    case .audioBufferCopyFailed:
      return "AUDIO_BUFFER_COPY_FAILED"
    case .audioConversionUnavailable:
      return "AUDIO_CONVERSION_UNAVAILABLE"
    case .audioConversionFailed:
      return "AUDIO_CONVERSION_FAILED"
    case .audioBufferTimeout:
      return "AUDIO_BUFFER_TIMEOUT"
    case .noSpeech:
      return "NO_SPEECH"
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    audioSessionCoordinator.attachTraceSink { [weak self] payload in
      guard let self, !self.disposed else { return }
      events(payload)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    audioSessionCoordinator.detachTraceSink()
    return nil
  }

  func dispose() {
    guard !disposed else { return }
    startRequestGeneration += 1
    cancelCurrent(
      deleteRecording: true,
      caller: "IOSSpeechRecognizerBridge.dispose"
    )
    audioSessionCoordinator.endMainTurn(
      reason: "speech_bridge_disposed",
      caller: "IOSSpeechRecognizerBridge.dispose"
    )
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
  private let inputStream: AsyncStream<AnalyzerInput>
  private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
  private var audioConverter: AVAudioConverter?
  private var analysisTask: Task<Void, Never>?
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
    inputStream = stream.stream
    inputContinuation = stream.continuation
  }

  /// Starts result consumption only after the bridge has installed onUpdate and
  /// onFailure. Starting these tasks inside init could lose an immediate
  /// SpeechAnalyzer failure and leave Dart waiting after the ready cue.
  func start() {
    guard analysisTask == nil, resultTask == nil else { return }
    let analyzer = self.analyzer
    let inputStream = self.inputStream
    analysisTask = Task { [weak self] in
      do {
        let lastSample = try await analyzer.analyzeSequence(inputStream)
        if let lastSample {
          try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
          await analyzer.cancelAndFinishNow()
        }
      } catch is CancellationError {
        return
      } catch {
        self?.onFailure?(error)
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

  @discardableResult
  func append(_ buffer: AVAudioPCMBuffer) throws -> Int {
    if let convertedBuffer = try convert(buffer) {
      inputContinuation.yield(AnalyzerInput(buffer: convertedBuffer))
      return 1
    }
    return 0
  }

  func stop() async throws -> IOSAnalyzerTranscript {
    for convertedBuffer in try flushAudioConverter() {
      inputContinuation.yield(AnalyzerInput(buffer: convertedBuffer))
    }
    inputContinuation.finish()
    await analysisTask?.value
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
    // Avoid an unnecessary sample-rate conversion when AVAudioEngine already
    // supplies SpeechAnalyzer's preferred format.
    if inputBuffer.format.isEqual(analyzerFormat) {
      return inputBuffer
    }

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
  case builtInMicUnavailable
  case hfpInputUnavailable
  case audioRouteMismatch(expected: String, actual: String)
  case audioInputUnavailable
  case audioBufferCopyFailed
  case audioConversionUnavailable
  case audioConversionFailed
  case audioBufferTimeout
  case noSpeech
  case startCancelled

  var errorDescription: String? {
    switch self {
    case .onDeviceUnavailable:
      return "Thiết bị chưa hỗ trợ nhận dạng tiếng Việt on-device."
    case .builtInMicUnavailable:
      return "iOS không tìm thấy micro tích hợp để mở MAIN."
    case .hfpInputUnavailable:
      return "iOS chưa có đầu vào bluetoothHFP đang khả dụng."
    case let .audioRouteMismatch(expected, actual):
      return "Audio route không đúng nguồn \(expected). Route hiện tại: \(actual)"
    case .audioInputUnavailable:
      return "iOS chưa mở được micro iPhone hoặc H20 HFP."
    case .audioBufferCopyFailed:
      return "iOS chưa sao chép được luồng micro cho Apple Speech."
    case .audioConversionUnavailable:
      return "iOS chưa tạo được bộ chuyển đổi âm thanh cho Apple Speech."
    case .audioConversionFailed:
      return "iOS chưa chuyển đổi được âm thanh cho Apple Speech."
    case .audioBufferTimeout:
      return "Audio route đã mở nhưng Apple Speech chưa nhận được dữ liệu micro."
    case .noSpeech:
      return "Mình chưa nghe rõ. Con thử nói lại gần micro hơn nhé."
    case .startCancelled:
      return "Lượt mở Apple Speech đã được thay thế hoặc hủy."
    }
  }
}
