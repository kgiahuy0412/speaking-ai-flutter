import AVFoundation
import AudioToolbox
import Flutter
import Foundation

/// Native iOS prompt output for the fixed MAIN assistant. Keeping prompts in
/// AVSpeechSynthesizer avoids a network round trip before command recognition.
final class VoicePromptBridge: NSObject, AVSpeechSynthesizerDelegate {
  private let channel: FlutterMethodChannel
  private let synthesizer = AVSpeechSynthesizer()
  private var waitingResult: FlutterResult?
  private var readyCueResult: FlutterResult?
  private var readyCueToken: UUID?
  private var readyCueFallback: DispatchWorkItem?
  private var disposed = false

  init(messenger: FlutterBinaryMessenger) {
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
    case "speak", "speakAndWait":
      let arguments = call.arguments as? [String: Any]
      let text = (arguments?["text"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let locale = arguments?["locale"] as? String ?? "vi-VN"
      speak(text, locale: locale, waitForCompletion: call.method == "speakAndWait", result: result)
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
    waitForCompletion: Bool,
    result: @escaping FlutterResult
  ) {
    guard !text.isEmpty else {
      result(nil)
      return
    }
    stop()
    configureAudioSession()
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

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
    )
    try? session.setActive(true)
  }

  private func stop() {
    if synthesizer.isSpeaking || synthesizer.isPaused {
      synthesizer.stopSpeaking(at: .immediate)
    }
    completeWaitingResult()
    completeReadyCue()
  }

  private func completeWaitingResult() {
    let result = waitingResult
    waitingResult = nil
    result?(nil)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    completeWaitingResult()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    completeWaitingResult()
  }

  private func playSpeechReadyCue(_ result: @escaping FlutterResult) {
    completeReadyCue()
    configureAudioSession()

    let token = UUID()
    readyCueToken = token
    readyCueResult = result
    let fallback = DispatchWorkItem { [weak self] in
      self?.completeReadyCue(token: token)
    }
    readyCueFallback = fallback

    AudioServicesPlaySystemSoundWithCompletion(1104) { [weak self] in
      DispatchQueue.main.async {
        self?.completeReadyCue(token: token)
      }
    }
    // Some iOS/HFP combinations do not deliver the system-sound completion
    // callback. Release Flutter after a bounded cue interval so recognition
    // can still start immediately after the prompt.
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(650),
      execute: fallback
    )
  }

  private func completeReadyCue(token: UUID? = nil) {
    if let token, token != readyCueToken {
      return
    }
    readyCueFallback?.cancel()
    readyCueFallback = nil
    readyCueToken = nil
    let result = readyCueResult
    readyCueResult = nil
    result?(nil)
  }

  func dispose() {
    guard !disposed else { return }
    stop()
    disposed = true
    synthesizer.delegate = nil
    channel.setMethodCallHandler(nil)
  }
}
