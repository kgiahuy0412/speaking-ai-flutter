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
