import Flutter
import Foundation
import UIKit

final class BackgroundLearningBridge: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let audioSessionCoordinator: IOSAudioSessionCoordinator
  private var eventSink: FlutterEventSink?
  private var activeLearningRequested = false
  private var willResignActiveToken: NSObjectProtocol?
  private var didEnterBackgroundToken: NSObjectProtocol?
  private var willEnterForegroundToken: NSObjectProtocol?
  private var didBecomeActiveToken: NSObjectProtocol?

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

    willResignActiveToken = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.audioSessionCoordinator.requestBackgroundCaptureArm(
        caller: "BackgroundLearningBridge.willResignActive"
      )
      self.reconcileBackgroundTransitionLease()
    }
    didEnterBackgroundToken = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.audioSessionCoordinator.applicationDidEnterBackground()
      self?.reconcileBackgroundTransitionLease()
    }
    willEnterForegroundToken = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.audioSessionCoordinator.applicationWillEnterForeground()
      self?.audioSessionCoordinator.setBackgroundTransitionLeaseActive(false)
    }
    didBecomeActiveToken = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      if !IOSBackgroundAudioHandoffPolicy.shouldKeepEngineRunning(
        backgroundLearningEnabled: self.audioSessionCoordinator.isBackgroundLearningEnabled,
        applicationIsActive: true
      ) {
        self.audioSessionCoordinator.requestBackgroundCaptureDisarm(
          caller: "BackgroundLearningBridge.didBecomeActive"
        )
      }
    }

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
        self.activeLearningRequested = false
        self.audioSessionCoordinator.setBackgroundTransitionLeaseActive(false)
        self.audioSessionCoordinator.setBackgroundLearningEnabled(false)
        result(nil)
      case "setActiveLearning":
        let arguments = call.arguments as? [String: Any]
        self.activeLearningRequested = arguments?["active"] as? Bool ?? false
        if self.activeLearningRequested {
          self.audioSessionCoordinator.requestBackgroundCaptureArm(
            caller: "BackgroundLearningBridge.setActiveLearning"
          )
        } else if !IOSBackgroundAudioHandoffPolicy.shouldKeepEngineRunning(
          backgroundLearningEnabled: self.audioSessionCoordinator.isBackgroundLearningEnabled,
          applicationIsActive: UIApplication.shared.applicationState == .active
        ) {
          self.audioSessionCoordinator.requestBackgroundCaptureDisarm(
            caller: "BackgroundLearningBridge.setActiveLearningEnded"
          )
        }
        self.reconcileBackgroundTransitionLease()
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
    activeLearningRequested = false
    audioSessionCoordinator.setBackgroundTransitionLeaseActive(false)
    audioSessionCoordinator.setBackgroundLearningEnabled(false)
    audioSessionCoordinator.onBackgroundLearningEvent = nil
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
    eventSink = nil
    if let willResignActiveToken {
      NotificationCenter.default.removeObserver(willResignActiveToken)
    }
    willResignActiveToken = nil
    if let didEnterBackgroundToken {
      NotificationCenter.default.removeObserver(didEnterBackgroundToken)
    }
    didEnterBackgroundToken = nil
    if let willEnterForegroundToken {
      NotificationCenter.default.removeObserver(willEnterForegroundToken)
    }
    willEnterForegroundToken = nil
    if let didBecomeActiveToken {
      NotificationCenter.default.removeObserver(didBecomeActiveToken)
    }
    didBecomeActiveToken = nil
  }

  private func reconcileBackgroundTransitionLease() {
    let shouldRetain = activeLearningRequested
      && UIApplication.shared.applicationState != .active
    audioSessionCoordinator.setBackgroundTransitionLeaseActive(shouldRetain)
  }
}
