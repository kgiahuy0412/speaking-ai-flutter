import Flutter
@testable import Runner
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testAiv0DuplicatePacketFilterUsesAndroidParityWindow() {
    var filter = Aiv0DuplicatePacketFilter()

    XCTAssertFalse(filter.register(rawHex: "01 01", uptimeMilliseconds: 1_000))
    XCTAssertTrue(filter.register(rawHex: "01 01", uptimeMilliseconds: 1_750))
    XCTAssertEqual(filter.duplicateCount, 1)
    XCTAssertFalse(filter.register(rawHex: "01 02", uptimeMilliseconds: 1_800))

    filter.resetWindow()
    XCTAssertFalse(filter.register(rawHex: "01 02", uptimeMilliseconds: 1_900))
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

}
