import Flutter
@testable import Runner
import StoreKit
import StoreKitTest
import UIKit
import XCTest

final class RunnerTests: XCTestCase {
  private let productIds = [
    "com.kong373.voiceSocialApp.recharge.60",
    "com.kong373.voiceSocialApp.recharge.300",
    "com.kong373.voiceSocialApp.recharge.980",
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
      productIdentifier: "com.kong373.voiceSocialApp.recharge.60"
    )

    let transactions = session.allTransactions()
    XCTAssertEqual(transactions.count, 1)
    XCTAssertEqual(
      transactions.first?.productIdentifier,
      "com.kong373.voiceSocialApp.recharge.60"
    )
  }

  @available(iOS 15.0, *)
  func testStoreKitTestAskToBuyCanBeDeclined() async throws {
    let session = try makeStoreKitSession()
    session.disableDialogs = true
    session.clearTransactions()
    session.askToBuyEnabled = true

    let products = try await Product.products(for: [productIds[1]])
    let product = try XCTUnwrap(products.first)
    let result = try await product.purchase()
    guard case .pending = result else {
      XCTFail("Ask to Buy must remain pending until approval")
      return
    }

    let transaction = try XCTUnwrap(session.allTransactions().first)
    XCTAssertEqual(transaction.state, .deferred)
    XCTAssertEqual(
      transaction.productIdentifier,
      "com.kong373.voiceSocialApp.recharge.300"
    )
    try session.declineAskToBuyTransaction(
      identifier: transaction.identifier
    )
    XCTAssertFalse(session.allTransactions().contains { $0.state == .purchased })
  }

  @available(iOS 15.0, *)
  func testStoreKitPurchaseFlightHoldsGuardUntilLocalPurchaseReturns() async throws {
    let session = try makeStoreKitSession()
    session.disableDialogs = true
    session.clearTransactions()
    session.askToBuyEnabled = true

    let products = try await Product.products(for: [productIds[0]])
    let product = try XCTUnwrap(products.first)
    let flight = await StoreKit2PurchaseFlight()
    let gate = ReleaseGate()
    let entered = expectation(description: "first purchase owns the flight")

    let first = Task { @MainActor in
      try await flight.run(productId: product.id) {
        entered.fulfill()
        await gate.wait()
        return try await product.purchase()
      }
    }
    await fulfillment(of: [entered], timeout: 1)

    do {
      _ = try await flight.run(productId: product.id) {
        XCTFail("a repeated product purchase must not call StoreKit")
        return try await product.purchase()
      }
      XCTFail("the repeated product purchase should be rejected")
    } catch is StoreKit2PurchaseFlightError {
      // The native uncertainty remains owned by the first operation.
    }

    do {
      _ = try await flight.run(productId: productIds[1]) {
        XCTFail("a different product must also be rejected while a purchase is in flight")
        return try await product.purchase()
      }
      XCTFail("the global native purchase flight should reject another product")
    } catch is StoreKit2PurchaseFlightError {
      // StoreKit purchase is globally singleflight on this coordinator.
    }

    await gate.release()
    let result = try await first.value
    guard case .pending = result else {
      XCTFail("Ask to Buy should keep the local purchase pending")
      return
    }

    let retry = try await flight.run(productId: product.id) {
      try await product.purchase()
    }
    guard case .pending = retry else {
      XCTFail("the flight must be reusable after the first native return")
      return
    }
  }

  @available(iOS 15.0, *)
  private func makeStoreKitSession() throws -> SKTestSession {
    let configuration = try XCTUnwrap(
      Bundle(for: RunnerTests.self).url(
        forResource: "VoiceSocial", withExtension: "storekit"
      )
    )
    let session = try SKTestSession(contentsOf: configuration)
    session.resetToDefaultState()
    addTeardownBlock {
      session.clearTransactions()
      session.resetToDefaultState()
    }
    return session
  }
}

private actor ReleaseGate {
  private var released = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if released {
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func release() {
    released = true
    let pending = waiters
    waiters.removeAll()
    for waiter in pending {
      waiter.resume()
    }
  }
}
