import AVFoundation
import Flutter
@testable import Runner
import Speech
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testAiv0DuplicatePacketFilterUsesAndroidParityWindow() {
    var filter = Aiv0DuplicatePacketFilter()

    XCTAssertFalse(filter.register(bytes: [0x01, 0x01], uptimeMilliseconds: 1_000))
    XCTAssertTrue(filter.register(bytes: [0x01, 0x01], uptimeMilliseconds: 1_750))
    XCTAssertEqual(filter.duplicateCount, 1)
    XCTAssertFalse(filter.register(bytes: [0x01, 0x02], uptimeMilliseconds: 1_800))

    filter.resetWindow()
    XCTAssertFalse(filter.register(bytes: [0x01, 0x02], uptimeMilliseconds: 1_900))
    XCTAssertEqual(filter.duplicateCount, 1)
  }

  func testAiv0DuplicatePacketFilterCollapsesObservedH20MainBurst() {
    var filter = Aiv0DuplicatePacketFilter()
    let packets: [[UInt8]] = [
      [0x01, 0x01, 0x06, 0x01, 0x01, 0x00, 0x39, 0x00, 0x83, 0x8C, 0x03, 0x00],
      [0x01, 0x01, 0x07, 0x01, 0x01, 0x00, 0x39, 0x00, 0x2B, 0x8F, 0x03, 0x00],
      [0x01, 0x01, 0x08, 0x01, 0x01, 0x00, 0x39, 0x00, 0xF3, 0x8F, 0x03, 0x00],
      [0x01, 0x01, 0x09, 0x01, 0x01, 0x00, 0x39, 0x00, 0xBB, 0x90, 0x03, 0x00],
      [0x01, 0x01, 0x0A, 0x01, 0x01, 0x00, 0x39, 0x00, 0x4B, 0x92, 0x03, 0x00],
    ]

    XCTAssertFalse(filter.register(bytes: packets[0], uptimeMilliseconds: 1_000))
    for (index, packet) in packets.dropFirst().enumerated() {
      XCTAssertTrue(
        filter.register(
          bytes: packet,
          uptimeMilliseconds: 1_200 + TimeInterval(index * 200)
        )
      )
    }
    XCTAssertEqual(filter.duplicateCount, 4)

    XCTAssertFalse(filter.register(bytes: packets[0], uptimeMilliseconds: 2_751))
  }

  func testAiv0DuplicatePacketFilterAcceptsANewMainAfterTheQuietWindow() {
    var filter = Aiv0DuplicatePacketFilter()
    let mainPacket: [UInt8] = [
      0x01, 0x01, 0x10, 0x01, 0x01, 0x00, 0x39, 0x00, 0x00, 0x10, 0x00, 0x00,
    ]

    XCTAssertFalse(filter.register(bytes: mainPacket, uptimeMilliseconds: 1_000))
    XCTAssertTrue(filter.register(bytes: mainPacket, uptimeMilliseconds: 1_750))
    XCTAssertFalse(filter.register(bytes: mainPacket, uptimeMilliseconds: 2_501))
    XCTAssertEqual(filter.duplicateCount, 1)
  }

  func testAiv0ReconnectPolicyUsesBoundedExponentialBackoff() {
    XCTAssertEqual(Aiv0ReconnectPolicy.maxAttempts, 3)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 1), 1)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 2), 2)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 3), 4)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 4), 4)
    XCTAssertEqual(Aiv0ReconnectPolicy.attemptTimeoutSeconds, 10)
    XCTAssertTrue(
      Aiv0ReconnectPolicy.shouldDeferReconnect(
        mainTurnActive: true,
        promptActive: false,
        speechCaptureActive: false,
        hfpRouteActive: false
      )
    )
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferReconnect(
        mainTurnActive: false,
        promptActive: false,
        speechCaptureActive: false,
        hfpRouteActive: false
      )
    )
    XCTAssertTrue(
      Aiv0ReconnectPolicy.shouldDeferReconnect(
        mainTurnActive: false,
        promptActive: false,
        speechCaptureActive: false,
        hfpRouteActive: true
      )
    )
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferNotificationMaintenance(
        mainTurnActive: false,
        speechCaptureActive: false,
        hfpRouteActive: true
      )
    )
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferNotificationMaintenance(
        mainTurnActive: false,
        speechCaptureActive: false,
        hfpRouteActive: false
      )
    )
    XCTAssertTrue(
      Aiv0ReconnectPolicy.shouldDeferNotificationMaintenance(
        mainTurnActive: false,
        speechCaptureActive: true,
        hfpRouteActive: true
      )
    )
  }

  func testAiv0ReconnectPolicyDefersEveryLiveAudioCriticalSection() {
    XCTAssertTrue(
      Aiv0ReconnectPolicy.shouldDeferReconnect(
        mainTurnActive: false,
        promptActive: true,
        speechCaptureActive: false,
        hfpRouteActive: false
      )
    )
    XCTAssertTrue(
      Aiv0ReconnectPolicy.shouldDeferReconnect(
        mainTurnActive: false,
        promptActive: false,
        speechCaptureActive: true,
        hfpRouteActive: false
      )
    )
  }

  func testIOSHfpIdleRouteReleaseWaitsForTheAuthoritativeRouteChange() {
    XCTAssertEqual(
      IOSHfpIdleRouteReleasePolicy.nextStep(
        hasTwoWayHfpRoute: true,
        attemptsRemaining: 20
      ),
      .wait
    )
    XCTAssertEqual(
      IOSHfpIdleRouteReleasePolicy.nextStep(
        hasTwoWayHfpRoute: false,
        attemptsRemaining: 20
      ),
      .complete
    )
    XCTAssertEqual(
      IOSHfpIdleRouteReleasePolicy.nextStep(
        hasTwoWayHfpRoute: true,
        attemptsRemaining: 0
      ),
      .timedOut
    )
  }

  func testIOSAudioOwnershipKeepsPromptAliveWhenMainTurnEnds() {
    var ownership = IOSAudioSessionOwnershipState()

    ownership.acquire(.mainTurn)
    ownership.acquire(.prompt)
    ownership.release(.mainTurn)

    XCTAssertFalse(ownership.canDeactivate)
    XCTAssertEqual(ownership.activeOwners, [.prompt])

    ownership.release(.prompt)
    XCTAssertTrue(ownership.canDeactivate)
  }

  func testIOSAudioOwnershipKeepsHfpRouteAcrossSpeechHandoffs() {
    var ownership = IOSAudioSessionOwnershipState()

    ownership.acquire(.hfpRoute)
    ownership.acquire(.speechCapture)
    ownership.release(.speechCapture)

    XCTAssertFalse(ownership.canDeactivate)
    XCTAssertEqual(ownership.activeOwners, [.hfpRoute])

    ownership.release(.hfpRoute)
    XCTAssertTrue(ownership.canDeactivate)
  }

  func testIOSAudioOwnershipOnlyReportsARealCaptureReleaseOnce() {
    var ownership = IOSAudioSessionOwnershipState()

    XCTAssertFalse(ownership.contains(.speechCapture))
    XCTAssertFalse(ownership.release(.speechCapture))
    ownership.acquire(.speechCapture)
    XCTAssertTrue(ownership.contains(.speechCapture))
    XCTAssertTrue(ownership.release(.speechCapture))
    XCTAssertFalse(ownership.release(.speechCapture))
  }

  func testIOSAudioOwnershipRequiresEverySameOwnerLeaseToRelease() {
    var ownership = IOSAudioSessionOwnershipState()

    ownership.acquire(.prompt)
    ownership.acquire(.prompt)

    XCTAssertTrue(ownership.release(.prompt))
    XCTAssertFalse(ownership.canDeactivate)
    XCTAssertEqual(ownership.activeOwners, [.prompt])

    XCTAssertTrue(ownership.release(.prompt))
    XCTAssertTrue(ownership.canDeactivate)
  }

  func testVoicePromptLeaseIgnoresAStaleCompletionFromThePreviousPrompt() {
    var lease = IOSPromptOperationLeaseState()
    let firstPrompt = UUID()
    let secondPrompt = UUID()

    lease.activate(firstPrompt)
    XCTAssertTrue(lease.release(firstPrompt))

    lease.activate(secondPrompt)
    XCTAssertFalse(lease.release(firstPrompt))
    XCTAssertEqual(lease.activeToken, secondPrompt)
    XCTAssertTrue(lease.release(secondPrompt))
    XCTAssertNil(lease.activeToken)
  }

  func testIOSHfpRouteLeaseReleasesAtUtteranceBoundary() {
    var lease = IOSHfpRouteLeaseState()

    XCTAssertTrue(lease.acquireIfNeeded())
    XCTAssertFalse(lease.acquireIfNeeded())
    XCTAssertTrue(lease.isHeld)

    XCTAssertTrue(lease.finishUtterance())
    XCTAssertFalse(lease.finishUtterance())
    XCTAssertFalse(lease.isHeld)
  }

  func testAiv0MainNotificationRefreshPreservesAHealthySubscription() {
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        refreshInProgress: false,
        isNotifying: true
      ),
      .complete
    )
  }

  func testAiv0MainNotificationRecoveryRearmsAStaleSubscriptionAfterHfpTurn() {
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        recoveryMode: .forceDisable,
        isNotifying: true
      ),
      .disable
    )
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        recoveryMode: .forceEnable,
        isNotifying: false
      ),
      .enable
    )
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        recoveryMode: .forceEnable,
        isNotifying: true
      ),
      .complete
    )
  }

  func testAiv0DeferredRecoveryNeverReconnectsAnAttachedPeripheral() {
    XCTAssertEqual(
      Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: true,
        peripheralConnected: true,
        hasButtonCharacteristic: true
      ),
      .wait
    )
    XCTAssertEqual(
      Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: false,
        peripheralConnected: true,
        hasButtonCharacteristic: true
      ),
      .rearmNotification
    )
    XCTAssertEqual(
      Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: false,
        peripheralConnected: true,
        hasButtonCharacteristic: false
      ),
      .rediscover
    )
    XCTAssertEqual(
      Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: false,
        peripheralConnected: false,
        hasButtonCharacteristic: false
      ),
      .reconnect
    )
  }

  func testAiv0MainNotificationRefreshEnablesOnlyAMissingSubscription() {
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        refreshInProgress: false,
        isNotifying: false
      ),
      .enable
    )
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        refreshInProgress: true,
        isNotifying: false
      ),
      .enable
    )
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        refreshInProgress: true,
        isNotifying: true
      ),
      .complete
    )
  }

  func testAiv0MainNotificationRefreshSkipsAnUnavailableGattLink() {
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: false,
        hasButtonCharacteristic: true,
        refreshInProgress: false,
        isNotifying: true
      ),
      .reconnect
    )
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: false,
        refreshInProgress: false,
        isNotifying: false
      ),
      .rediscover
    )
  }

  func testAiv0ConnectStartPreservesAnAlreadyReadyGattSession() {
    XCTAssertEqual(
      Aiv0ConnectStartPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        hasStateCharacteristic: true,
        isNotifying: true
      ),
      .complete
    )
  }

  func testAiv0ConnectStartRediscoversWithoutReconnectingAnAttachedPeripheral() {
    XCTAssertEqual(
      Aiv0ConnectStartPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: false,
        hasStateCharacteristic: false,
        isNotifying: false
      ),
      .rediscover
    )
  }

  func testAiv0ConnectStartRestoresOnlyAMissingNotification() {
    XCTAssertEqual(
      Aiv0ConnectStartPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        hasStateCharacteristic: true,
        isNotifying: false
      ),
      .enable
    )
  }

  func testAiv0ConnectStartConnectsOnlyADisconnectedPeripheral() {
    XCTAssertEqual(
      Aiv0ConnectStartPolicy.nextStep(
        peripheralConnected: false,
        hasButtonCharacteristic: false,
        hasStateCharacteristic: false,
        isNotifying: false
      ),
      .connect
    )
  }

  func testAiv0InitialNotificationSetupCompletesAnExistingSubscription() {
    XCTAssertEqual(
      Aiv0InitialNotificationSetupPolicy.nextStep(isNotifying: true),
      .complete
    )
    XCTAssertEqual(
      Aiv0InitialNotificationSetupPolicy.nextStep(isNotifying: false),
      .enable
    )
  }

  func testIOSAudioCoordinatorPromotesPhysicalMainIntoOneTurnTimeline() {
    let coordinator = IOSAudioSessionCoordinator()
    var timeline: [[String: Any]] = []
    coordinator.attachTraceSink { timeline.append($0) }

    coordinator.notePhysicalMain(rawHex: "01 01 01 01")
    let turnId = coordinator.beginMainTurn(source: "RunnerTests")

    let rawEvent = timeline.first {
      ($0["stage"] as? String) == "main_raw_received"
    }
    XCTAssertEqual(rawEvent?["turnId"] as? String, turnId)
    XCTAssertTrue(
      timeline.contains { ($0["stage"] as? String) == "main_turn_started" }
    )
    XCTAssertTrue(coordinator.isMainTurnActive)

    coordinator.endMainTurn(reason: "test_complete", caller: "RunnerTests")
    XCTAssertFalse(coordinator.isMainTurnActive)
    let lastMainTurnStage = timeline.reversed().compactMap {
      $0["stage"] as? String
    }.first { $0.hasPrefix("main_turn_") }
    XCTAssertEqual(lastMainTurnStage, "main_turn_ended")
    XCTAssertTrue(
      timeline.contains {
        ($0["stage"] as? String) == "audio_session_release_requested"
      }
    )
    coordinator.dispose()
  }

  func testIOSAudioCoordinatorIgnoresStaleMainTurnEnd() {
    let coordinator = IOSAudioSessionCoordinator()
    var timeline: [[String: Any]] = []
    coordinator.attachTraceSink { timeline.append($0) }

    let turnId = coordinator.beginMainTurn(source: "RunnerTests")
    coordinator.endMainTurn(
      reason: "late_controller_pause",
      caller: "RunnerTests",
      expectedTurnId: "obsolete-turn"
    )

    XCTAssertTrue(coordinator.isMainTurnActive)
    let stageAfterStaleEnd = timeline.reversed().compactMap {
      $0["stage"] as? String
    }.first { $0.hasPrefix("main_turn_") }
    XCTAssertEqual(stageAfterStaleEnd, "main_turn_end_stale_ignored")

    coordinator.endMainTurn(
      reason: "test_complete",
      caller: "RunnerTests",
      expectedTurnId: turnId
    )
    XCTAssertFalse(coordinator.isMainTurnActive)
    let stageAfterValidEnd = timeline.reversed().compactMap {
      $0["stage"] as? String
    }.first { $0.hasPrefix("main_turn_") }
    XCTAssertEqual(stageAfterValidEnd, "main_turn_ended")
    XCTAssertTrue(
      timeline.contains {
        ($0["stage"] as? String) == "audio_session_release_requested"
      }
    )
    coordinator.dispose()
  }

  func testIOSAudioCoordinatorGivesASecondPhysicalPressAFreshTurn() {
    let coordinator = IOSAudioSessionCoordinator()
    var timeline: [[String: Any]] = []
    coordinator.attachTraceSink { timeline.append($0) }

    coordinator.notePhysicalMain(rawHex: "01 01 01 01")
    let firstTurnId = coordinator.beginMainTurn(source: "RunnerTests.first")

    coordinator.notePhysicalMain(rawHex: "01 01 02 01")
    let secondRawEvent = timeline.last {
      ($0["stage"] as? String) == "main_raw_received"
    }
    let secondTurnId = coordinator.beginMainTurn(source: "RunnerTests.second")

    XCTAssertNotEqual(secondTurnId, firstTurnId)
    XCTAssertEqual(secondRawEvent?["turnId"] as? String, secondTurnId)
    XCTAssertTrue(
      timeline.contains {
        ($0["stage"] as? String) == "main_turn_superseded"
          && ($0["previousTurnId"] as? String) == firstTurnId
      }
    )

    coordinator.endMainTurn(
      reason: "late_first_turn_cleanup",
      caller: "RunnerTests",
      expectedTurnId: firstTurnId
    )
    XCTAssertTrue(coordinator.isMainTurnActive)
    XCTAssertEqual(
      timeline.last { ($0["stage"] as? String)?.hasPrefix("main_turn_") == true }?["stage"] as? String,
      "main_turn_end_stale_ignored"
    )

    coordinator.endMainTurn(
      reason: "test_complete",
      caller: "RunnerTests",
      expectedTurnId: secondTurnId
    )
    XCTAssertFalse(coordinator.isMainTurnActive)
    coordinator.dispose()
  }

  func testIOSNativeSpeechPrefersSpeechAnalyzerOnIOS26() {
    XCTAssertEqual(
      IOSNativeSpeechEngineSelector.select(
        isIOS26OrNewer: true,
        speechAnalyzerSupported: true,
        sfOnDeviceSupported: true
      ),
      .speechAnalyzer
    )
  }

  func testIOSNativeSpeechFallsBackOnlyToOnDeviceLegacyRecognizer() {
    XCTAssertEqual(
      IOSNativeSpeechEngineSelector.select(
        isIOS26OrNewer: true,
        speechAnalyzerSupported: false,
        sfOnDeviceSupported: true
      ),
      .sfSpeechRecognizer
    )
    XCTAssertNil(
      IOSNativeSpeechEngineSelector.select(
        isIOS26OrNewer: false,
        speechAnalyzerSupported: false,
        sfOnDeviceSupported: false
      )
    )
  }

  func testIOSMainUsesDictationForVietnameseNavigationPhrases() {
    XCTAssertEqual(
      IOSNativeSpeechTaskHintSelector.select(commandMode: true),
      .dictation
    )
  }

  func testIOSMainKeepsPreparedSpeechAnalyzerOnIOS26() {
    XCTAssertEqual(
      IOSNativeSpeechEngineSelector.selectForRecognition(
        preparedEngine: .speechAnalyzer,
        commandMode: true,
        sfOnDeviceSupported: true
      ),
      .speechAnalyzer
    )
    XCTAssertEqual(
      IOSNativeSpeechEngineSelector.selectForRecognition(
        preparedEngine: .speechAnalyzer,
        commandMode: false,
        sfOnDeviceSupported: true
      ),
      .speechAnalyzer
    )
  }

  func testIOSAudioBufferLevelReadsFloatAndInt16MicrophoneBuffers() throws {
    let floatFormat = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    )
    let floatBuffer = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: 4)
    )
    floatBuffer.frameLength = 4
    for index in 0..<4 {
      floatBuffer.floatChannelData?[0][index] = 0.5
    }

    let int16Format = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 8_000,
        channels: 1,
        interleaved: false
      )
    )
    let int16Buffer = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: int16Format, frameCapacity: 4)
    )
    int16Buffer.frameLength = 4
    for index in 0..<4 {
      int16Buffer.int16ChannelData?[0][index] = 16_384
    }

    XCTAssertEqual(try XCTUnwrap(IOSAudioBufferLevel.dbfs(floatBuffer)), -6.02, accuracy: 0.1)
    XCTAssertEqual(try XCTUnwrap(IOSAudioBufferLevel.dbfs(int16Buffer)), -6.02, accuracy: 0.1)
  }

  func testIOSBuiltInMicPolicyExcludesBluetoothOptions() {
    let options = IOSNativeSpeechAudioRoutePolicy.categoryOptions(
      for: .builtInMic
    )

    XCTAssertTrue(options.contains(.defaultToSpeaker))
    XCTAssertFalse(options.contains(.allowBluetoothHFP))
    XCTAssertFalse(options.contains(.allowBluetoothA2DP))
    XCTAssertTrue(
      IOSNativeSpeechAudioRoutePolicy.accepts(
        portType: .builtInMic,
        for: .builtInMic
      )
    )
    XCTAssertFalse(
      IOSNativeSpeechAudioRoutePolicy.accepts(
        portType: .bluetoothHFP,
        for: .builtInMic
      )
    )
  }

  func testIOSHfpPolicyRequiresARealBluetoothInputRoute() {
    let options = IOSNativeSpeechAudioRoutePolicy.categoryOptions(for: .hfp)

    XCTAssertTrue(options.contains(.allowBluetoothHFP))
    XCTAssertFalse(options.contains(.defaultToSpeaker))
    XCTAssertFalse(options.contains(.allowBluetoothA2DP))
    XCTAssertTrue(
      IOSNativeSpeechAudioRoutePolicy.accepts(
        portType: .bluetoothHFP,
        for: .hfp
      )
    )
    XCTAssertFalse(
      IOSNativeSpeechAudioRoutePolicy.accepts(
        portType: .bluetoothLE,
        for: .hfp
      )
    )
    XCTAssertFalse(
      IOSNativeSpeechAudioRoutePolicy.accepts(
        portType: .builtInMic,
        for: .hfp
      )
    )
    XCTAssertTrue(
      IOSHfpRoutePolicy.isTwoWayHfpRoute(
        inputTypes: [.bluetoothHFP],
        outputTypes: [.bluetoothHFP]
      )
    )
    XCTAssertFalse(
      IOSHfpRoutePolicy.isTwoWayHfpRoute(
        inputTypes: [.bluetoothHFP],
        outputTypes: [.builtInSpeaker]
      )
    )
  }

}
