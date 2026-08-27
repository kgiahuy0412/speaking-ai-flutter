import AVFoundation
import Flutter
import Foundation

/// Native iOS prompt output for the fixed MAIN assistant. Keeping prompts in
/// AVSpeechSynthesizer avoids a network round trip before command recognition.
final class VoicePromptBridge: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
  private let channel: FlutterMethodChannel
  private let audioSessionCoordinator: IOSAudioSessionCoordinator
  private let synthesizer = AVSpeechSynthesizer()
  private var waitingResult: FlutterResult?
  private var readyCueResult: FlutterResult?
  private var readyCueToken: UUID?
  private var readyCueFallback: DispatchWorkItem?
  private var readyCuePlayer: AVAudioPlayer?
  private var promptUsesHfpRoute = false
  private var disposed = false

  init(
    messenger: FlutterBinaryMessenger,
    audioSessionCoordinator: IOSAudioSessionCoordinator
  ) {
    self.audioSessionCoordinator = audioSessionCoordinator
    channel = FlutterMethodChannel(name: "ailingo_voice_prompt", binaryMessenger: messenger)
    super.init()
    synthesizer.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !disposed else {
      result(FlutterError(code: "VOICE_PROMPT_DISPOSED", message: "Bộ đọc đã đóng.", details: nil))
      return
    }
    switch call.method {
    case "beginMainTurn":
      result(audioSessionCoordinator.beginMainTurn(source: "VoicePromptBridge.beginMainTurn"))
    case "endMainTurn":
      let arguments = call.arguments as? [String: Any]
      audioSessionCoordinator.endMainTurn(
        reason: arguments?["reason"] as? String ?? "dart_requested",
        caller: "VoicePromptBridge.endMainTurn"
      )
      result(nil)
    case "speak", "speakAndWait":
      let arguments = call.arguments as? [String: Any]
      let text = (arguments?["text"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let locale = arguments?["locale"] as? String ?? "vi-VN"
      let forcePhoneSpeaker = arguments?["forcePhoneSpeaker"] as? Bool ?? false
      speak(
        text,
        locale: locale,
        forcePhoneSpeaker: forcePhoneSpeaker,
        waitForCompletion: call.method == "speakAndWait",
        result: result
      )
    case "playSpeechReadyCue":
      playSpeechReadyCue(result)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func speak(
    _ text: String,
    locale: String,
    forcePhoneSpeaker: Bool,
    waitForCompletion: Bool,
    result: @escaping FlutterResult
  ) {
    guard !text.isEmpty else {
      result(nil)
      return
    }
    stop()
    configurePromptAudioSession(forcePhoneSpeaker: forcePhoneSpeaker)
    audioSessionCoordinator.trace(stage: "prompt_started", caller: "VoicePromptBridge.speak")
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: locale)
      ?? AVSpeechSynthesisVoice(language: "vi-VN")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.volume = 1.0
    if waitForCompletion {
      waitingResult = result
    } else {
      result(nil)
    }
    synthesizer.speak(utterance)
  }

  private func configurePromptAudioSession(forcePhoneSpeaker: Bool = false) {
    let session = audioSessionCoordinator.session
    if forcePhoneSpeaker {
      do {
        try audioSessionCoordinator.preparePhoneSpeaker(
          caller: "VoicePromptBridge.configurePromptAudioSession"
        )
        promptUsesHfpRoute = false
      } catch {
        audioSessionCoordinator.trace(
          stage: "prompt_audio_error",
          caller: "VoicePromptBridge.configurePromptAudioSession",
          code: "PHONE_PROMPT_AUDIO_SESSION_FAILED",
          message: error.localizedDescription
        )
      }
      return
    }
    // Capture the HFP port before changing the shared session. HfpAudioBridge
    // activates and selects it; the prompt bridge must preserve that choice
    // instead of forcing every assistant utterance back to the iPhone speaker.
    let preferredHfpInput = session.currentRoute.inputs.first {
      IOSHfpRoutePolicy.isHfpInput($0.portType)
    } ?? session.availableInputs?.first {
      IOSHfpRoutePolicy.isHfpInput($0.portType)
    }
    do {
      promptUsesHfpRoute = try audioSessionCoordinator.preparePrompt(
        preferredHfpInput: preferredHfpInput,
        caller: "VoicePromptBridge.configurePromptAudioSession"
      )
    } catch {
      audioSessionCoordinator.trace(
        stage: "prompt_audio_error",
        caller: "VoicePromptBridge.configurePromptAudioSession",
        code: "PROMPT_AUDIO_SESSION_FAILED",
        message: error.localizedDescription
      )
    }
  }

  private func stop() {
    if synthesizer.isSpeaking || synthesizer.isPaused {
      synthesizer.stopSpeaking(at: .immediate)
    }
    completeWaitingResult()
    completeReadyCue()
    releasePromptAudioSession()
  }

  private func completeWaitingResult() {
    let result = waitingResult
    waitingResult = nil
    result?(nil)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    audioSessionCoordinator.trace(stage: "prompt_finished", caller: "VoicePromptBridge.didFinish")
    audioSessionCoordinator.trace(stage: "prompt_done", caller: "VoicePromptBridge.didFinish")
    releasePromptAudioSession()
    completeWaitingResult()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    audioSessionCoordinator.trace(stage: "prompt_cancelled", caller: "VoicePromptBridge.didCancel")
    releasePromptAudioSession()
    completeWaitingResult()
  }

  private func releasePromptAudioSession() {
    audioSessionCoordinator.releasePrompt(
      usedHfp: promptUsesHfpRoute,
      caller: "VoicePromptBridge.releasePromptAudioSession"
    )
  }

  private func playSpeechReadyCue(_ result: @escaping FlutterResult) {
    completeReadyCue()
    configurePromptAudioSession()
    audioSessionCoordinator.trace(stage: "ready_cue_started", caller: "VoicePromptBridge.playSpeechReadyCue")

    let token = UUID()
    readyCueToken = token
    readyCueResult = result
    let fallback = DispatchWorkItem { [weak self] in
      self?.completeReadyCue(token: token)
    }
    readyCueFallback = fallback

    do {
      let player = try AVAudioPlayer(data: Self.makeReadyCueWavData())
      player.delegate = self
      player.volume = 1.0
      player.numberOfLoops = 0
      player.prepareToPlay()
      readyCuePlayer = player
      guard player.play() else {
        throw ReadyCueError.playbackFailed
      }
    } catch {
      completeReadyCue(token: token)
      return
    }

    // AVAudioPlayer normally completes after 170 ms. Keep a bounded fallback
    // so a route interruption can never prevent Apple Speech from opening.
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(380),
      execute: fallback
    )
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    completeReadyCue()
  }

  private static func makeReadyCueWavData() -> Data {
    let sampleRate: UInt32 = 44_100
    let durationSeconds = 0.17
    let sampleCount = Int(Double(sampleRate) * durationSeconds)
    let dataByteCount = UInt32(sampleCount * MemoryLayout<Int16>.size)
    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    data.appendLittleEndian(UInt32(36) + dataByteCount)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    data.appendLittleEndian(UInt32(16))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(sampleRate)
    data.appendLittleEndian(sampleRate * UInt32(MemoryLayout<Int16>.size))
    data.appendLittleEndian(UInt16(MemoryLayout<Int16>.size))
    data.appendLittleEndian(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    data.appendLittleEndian(dataByteCount)

    let frequency = 880.0
    let fadeSamples = 220.0
    for index in 0..<sampleCount {
      let position = Double(index)
      let fadeIn = min(1.0, position / fadeSamples)
      let fadeOut = min(1.0, Double(sampleCount - index - 1) / fadeSamples)
      let envelope = min(fadeIn, fadeOut)
      let phase = 2.0 * Double.pi * frequency * position / Double(sampleRate)
      let value = sin(phase) * envelope * 0.42 * Double(Int16.max)
      data.appendLittleEndian(Int16(value.rounded()))
    }
    return data
  }

  private func completeReadyCue(token: UUID? = nil) {
    if let token, token != readyCueToken {
      return
    }
    let hadActiveCue = readyCueToken != nil || readyCueResult != nil || readyCuePlayer != nil
    readyCueFallback?.cancel()
    readyCueFallback = nil
    readyCuePlayer?.delegate = nil
    readyCuePlayer?.stop()
    readyCuePlayer = nil
    readyCueToken = nil
    let result = readyCueResult
    readyCueResult = nil
    if hadActiveCue {
      audioSessionCoordinator.trace(
        stage: "ready_cue_finished",
        caller: "VoicePromptBridge.completeReadyCue"
      )
    }
    // Hand AVAudioSession back before Dart opens AVAudioEngine. Without this
    // explicit release, the MAIN prompt can leave the speaker session active
    // and the following recognition start fails even though manual recording
    // works moments later.
    releasePromptAudioSession()
    result?(nil)
  }

  func dispose() {
    guard !disposed else { return }
    stop()
    audioSessionCoordinator.endMainTurn(
      reason: "prompt_bridge_disposed",
      caller: "VoicePromptBridge.dispose"
    )
    disposed = true
    synthesizer.delegate = nil
    channel.setMethodCallHandler(nil)
  }
}

private enum ReadyCueError: Error {
  case playbackFailed
}

private extension Data {
  mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var littleEndianValue = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
      append(contentsOf: bytes)
    }
  }
}
