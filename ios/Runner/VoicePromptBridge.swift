import AVFoundation
import Flutter
import Foundation

/// Native iOS prompt output for the fixed MAIN assistant. Keeping prompts in
/// AVSpeechSynthesizer avoids a network round trip before command recognition.
final class VoicePromptBridge: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
  private let channel: FlutterMethodChannel
  private let synthesizer = AVSpeechSynthesizer()
  private var waitingResult: FlutterResult?
  private var readyCueResult: FlutterResult?
  private var readyCueToken: UUID?
  private var readyCueFallback: DispatchWorkItem?
  private var readyCuePlayer: AVAudioPlayer?
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
    configurePromptAudioSession()
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

  private func configurePromptAudioSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    try? session.setCategory(
      .playAndRecord,
      mode: .default,
      options: [.defaultToSpeaker, .duckOthers]
    )
    try? session.setPreferredInput(nil)
    try? session.setActive(true)
    try? session.overrideOutputAudioPort(.speaker)
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
    releasePromptAudioSession()
    completeWaitingResult()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    releasePromptAudioSession()
    completeWaitingResult()
  }

  private func releasePromptAudioSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.overrideOutputAudioPort(.none)
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func playSpeechReadyCue(_ result: @escaping FlutterResult) {
    completeReadyCue()
    configurePromptAudioSession()

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
    readyCueFallback?.cancel()
    readyCueFallback = nil
    readyCuePlayer?.delegate = nil
    readyCuePlayer?.stop()
    readyCuePlayer = nil
    readyCueToken = nil
    let result = readyCueResult
    readyCueResult = nil
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
