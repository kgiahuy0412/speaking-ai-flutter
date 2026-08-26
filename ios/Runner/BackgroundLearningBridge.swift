import Flutter
import Foundation

final class BackgroundLearningBridge: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let audioSessionCoordinator: IOSAudioSessionCoordinator
  private var eventSink: FlutterEventSink?

  init(
    messenger: FlutterBinaryMessenger,
    audioSessionCoordinator: IOSAudioSessionCoordinator
  ) {
    self.audioSessionCoordinator = audioSessionCoordinator
    methodChannel = FlutterMethodChannel(
      name: "ailingo_background_learning",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "ailingo_background_learning/events",
      binaryMessenger: messenger
    )
    super.init()

    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "start":
        self.audioSessionCoordinator.setBackgroundLearningEnabled(true)
        result(true)
      case "stop":
        self.audioSessionCoordinator.setBackgroundLearningEnabled(false)
        result(nil)
      case "isActive":
        result(self.audioSessionCoordinator.isBackgroundLearningEnabled)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    eventChannel.setStreamHandler(self)
    audioSessionCoordinator.onBackgroundLearningEvent = { [weak self] payload in
      DispatchQueue.main.async {
        self?.eventSink?(payload)
      }
    }
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
    audioSessionCoordinator.setBackgroundLearningEnabled(false)
    audioSessionCoordinator.onBackgroundLearningEvent = nil
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
    eventSink = nil
  }
}
