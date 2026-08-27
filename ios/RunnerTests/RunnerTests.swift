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
    XCTAssertTrue(Aiv0ReconnectPolicy.shouldDefer(mainTurnActive: true))
    XCTAssertFalse(Aiv0ReconnectPolicy.shouldDefer(mainTurnActive: false))
  }

  func testIOSAudioCoordinatorPromotesPhysicalMainIntoOneTurnTimeline() {
    let coordinator = IOSAudioSessionCoordinator()
    var timeline: [[String: Any]] = []
    coordinator.attachTraceSink { timeline.append($0) }

    coordinator.notePhysicalMain(rawHex: "01 01 01 01")
    let turnId = coordinator.beginMainTurn(source: "RunnerTests")

    XCTAssertEqual(timeline.first?["turnId"] as? String, turnId)
    XCTAssertEqual(timeline.first?["stage"] as? String, "main_raw_received")
    XCTAssertEqual(timeline.last?["stage"] as? String, "main_turn_started")
    XCTAssertTrue(coordinator.isMainTurnActive)

    coordinator.endMainTurn(reason: "test_complete", caller: "RunnerTests")
    XCTAssertFalse(coordinator.isMainTurnActive)
    XCTAssertEqual(timeline.last?["stage"] as? String, "main_turn_ended")
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
    XCTAssertEqual(timeline.last?["stage"] as? String, "main_turn_end_stale_ignored")

    coordinator.endMainTurn(
      reason: "test_complete",
      caller: "RunnerTests",
      expectedTurnId: turnId
    )
    XCTAssertFalse(coordinator.isMainTurnActive)
    XCTAssertEqual(timeline.last?["stage"] as? String, "main_turn_ended")
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
    XCTAssertFalse(options.contains(.allowBluetooth))
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

    XCTAssertTrue(options.contains(.allowBluetooth))
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
