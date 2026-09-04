import XCTest

final class RunnerTests: XCTestCase {
  func testCommittedPurposeDescriptionsArePresent() throws {
    let info = try XCTUnwrap(Bundle.main.infoDictionary)

    XCTAssertFalse(
      try XCTUnwrap(info["NSMicrophoneUsageDescription"] as? String).isEmpty
    )
    XCTAssertFalse(
      try XCTUnwrap(info["NSPhotoLibraryUsageDescription"] as? String).isEmpty
    )
    XCTAssertFalse(
      try XCTUnwrap(info["NSPhotoLibraryAddUsageDescription"] as? String).isEmpty
    )
    XCTAssertFalse(
      try XCTUnwrap(info["NSCameraUsageDescription"] as? String).isEmpty
    )
    XCTAssertFalse(
      try XCTUnwrap(
        info["VoiceSocialNotificationUsageDescription"] as? String
      ).isEmpty
    )
  }

  func testDevelopmentBundleIdentifierIsExplicitlyAPlaceholder() {
    XCTAssertEqual(Bundle.main.bundleIdentifier, "com.kong373.voiceSocialApp")
  }
}
