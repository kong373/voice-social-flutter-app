import Flutter
import StoreKit
import StoreKitTest
import UIKit
import XCTest

final class RunnerTests: XCTestCase {
  private let productIds = [
    "com.kong373.voiceSocial.giftcoins.60",
    "com.kong373.voiceSocial.giftcoins.300",
  ]

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

  @available(iOS 15.0, *)
  func testLocalStoreKitConfigurationLoadsConsumables() async throws {
    let session = try makeStoreKitSession()
    session.disableDialogs = true
    session.clearTransactions()

    let products = try await Product.products(for: productIds)
    XCTAssertEqual(Set(products.map(\.id)), Set(productIds))
    XCTAssertTrue(products.allSatisfy { $0.type == .consumable })
  }

  @available(iOS 15.0, *)
  func testStoreKitTestCanCreateAnUnfinishedConsumable() async throws {
    let session = try makeStoreKitSession()
    session.disableDialogs = true
    session.clearTransactions()

    try session.buyProduct(
      productIdentifier: "com.kong373.voiceSocial.giftcoins.60"
    )

    let transactions = session.allTransactions()
    XCTAssertEqual(transactions.count, 1)
    XCTAssertEqual(
      transactions.first?.productIdentifier,
      "com.kong373.voiceSocial.giftcoins.60"
    )
  }

  @available(iOS 15.0, *)
  func testStoreKitTestAskToBuyCanBeDeclined() throws {
    let session = try makeStoreKitSession()
    session.disableDialogs = true
    session.clearTransactions()
    session.askToBuyEnabled = true

    try session.buyProduct(
      productIdentifier: "com.kong373.voiceSocial.giftcoins.300"
    )

    let transaction = try XCTUnwrap(session.allTransactions().first)
    XCTAssertEqual(
      transaction.productIdentifier,
      "com.kong373.voiceSocial.giftcoins.300"
    )
    try session.declineAskToBuyTransaction(
      identifier: transaction.identifier
    )
  }

  @available(iOS 15.0, *)
  private func makeStoreKitSession() throws -> SKTestSession {
    let sourceUrl = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("VoiceSocial.storekit")
    if FileManager.default.isReadableFile(atPath: sourceUrl.path) {
      return try SKTestSession(contentsOf: sourceUrl)
    }

    // Simulator test processes cannot always read the checkout's absolute
    // source path. Keep a local-only fallback so StoreKitTest stays hermetic
    // without App Store credentials or production product data.
    let temporaryUrl = FileManager.default.temporaryDirectory
      .appendingPathComponent("VoiceSocial-\(UUID().uuidString).storekit")
    let configuration = #"""
{
  "identifier" : "VOICE-SOCIAL-LOCAL-STOREKIT",
  "nonRenewingSubscriptions" : [],
  "products" : [
    {
      "displayPrice" : "6.00",
      "familyShareable" : false,
      "internalID" : "A6D70961-81A7-47A4-9895-3B26AAFE1001",
      "localizations" : [
        {
          "description" : "仅用于本地 StoreKit 自动化的 60 礼物币消耗型商品。",
          "displayName" : "60 礼物币",
          "locale" : "zh_CN"
        },
        {
          "description" : "Local StoreKit consumable for 60 gift coins.",
          "displayName" : "60 Gift Coins",
          "locale" : "en_US"
        }
      ],
      "productID" : "com.kong373.voiceSocial.giftcoins.60",
      "referenceName" : "Voice Social 60 Gift Coins",
      "type" : "Consumable"
    },
    {
      "displayPrice" : "30.00",
      "familyShareable" : false,
      "internalID" : "A6D70961-81A7-47A4-9895-3B26AAFE1002",
      "localizations" : [
        {
          "description" : "仅用于本地 StoreKit 自动化的 300 礼物币消耗型商品。",
          "displayName" : "300 礼物币",
          "locale" : "zh_CN"
        },
        {
          "description" : "Local StoreKit consumable for 300 gift coins.",
          "displayName" : "300 Gift Coins",
          "locale" : "en_US"
        }
      ],
      "productID" : "com.kong373.voiceSocial.giftcoins.300",
      "referenceName" : "Voice Social 300 Gift Coins",
      "type" : "Consumable"
    }
  ],
  "settings" : {
    "_applicationInternalID" : "0",
    "_developerTeamID" : "",
    "_failTransactionsEnabled" : false,
    "_locale" : "zh_CN",
    "_storefront" : "CHN",
    "_storeKitErrors" : []
  },
  "subscriptionGroups" : [],
  "version" : {
    "major" : 4,
    "minor" : 0
  }
}
"""#
    try Data(configuration.utf8).write(to: temporaryUrl, options: .atomic)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: temporaryUrl)
    }
    return try SKTestSession(contentsOf: temporaryUrl)
  }
}
