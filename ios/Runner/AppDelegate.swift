import Flutter
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // GeneratedPluginRegistrant wires first_party_native_permissions plus the
    // iOS implementations supplied by Agora, Tencent IM and secure storage.
    // No provider secret or signing material is accepted by this host.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "AppleIapStoreKit2Plugin"
    )
    AppleIapStoreKit2Plugin.register(with: registrar)
  }
}

private final class AppleIapStoreKit2Plugin: NSObject, FlutterPlugin,
  FlutterStreamHandler
{
  private static let methodChannelName =
    "voice_social_app/apple_iap_storekit2"
  private static let eventChannelName =
    "voice_social_app/apple_iap_storekit2/transactions"
  private static let maximumProductCount = 100
  private static let maximumIdentifierLength = 255
  private static let maximumJwsLength = 128 * 1024

  private var eventSink: FlutterEventSink?
  private var coordinatorObject: Any?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AppleIapStoreKit2Plugin()
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availability":
      availability(result: result)
    case "loadProducts":
      guard let productIds = productIdentifiers(from: call.arguments) else {
        result(invalidRequest("StoreKit product identifiers are invalid"))
        return
      }
      withCoordinator(result: result) { coordinator in
        try await coordinator.loadProducts(productIds)
      }
    case "purchase":
      guard
        let arguments = call.arguments as? [String: Any],
        let productId = boundedIdentifier(arguments["productId"]),
        let rawToken = arguments["appAccountToken"] as? String,
        let appAccountToken = UUID(uuidString: rawToken),
        rawToken.lowercased() == appAccountToken.uuidString.lowercased()
      else {
        result(invalidRequest("StoreKit purchase binding is invalid"))
        return
      }
      withCoordinator(result: result) { coordinator in
        try await coordinator.purchase(
          productId: productId,
          appAccountToken: appAccountToken
        )
      }
    case "recoverUnfinished":
      let synchronizeStore =
        (call.arguments as? [String: Any])?["synchronizeStore"] as? Bool
        ?? false
      withCoordinator(result: result) { coordinator in
        try await coordinator.recoverUnfinished(
          synchronizeStore: synchronizeStore
        )
      }
    case "finish":
      guard
        let arguments = call.arguments as? [String: Any],
        let transactionIdText = boundedIdentifier(arguments["transactionId"]),
        let transactionId = UInt64(transactionIdText)
      else {
        result(invalidRequest("StoreKit transaction identifier is invalid"))
        return
      }
      withCoordinator(result: result) { coordinator in
        try await coordinator.finish(transactionId: transactionId)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    guard #available(iOS 15.0, *) else {
      return nil
    }
    Task { @MainActor [weak self] in
      guard let self else { return }
      coordinator().startUpdates { [weak self] transaction in
        self?.eventSink?(transaction)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func availability(result: @escaping FlutterResult) {
    guard #available(iOS 15.0, *) else {
      result([
        "state": "unsupported_os",
        "minimumOsVersion": "15.0",
      ])
      return
    }
    result([
      "state": SKPaymentQueue.canMakePayments()
        ? "available"
        : "payments_disabled",
      "minimumOsVersion": "15.0",
    ])
  }

  private func withCoordinator(
    result: @escaping FlutterResult,
    operation: @escaping @MainActor (StoreKit2Coordinator) async throws -> Any
  ) {
    guard #available(iOS 15.0, *) else {
      result(unavailable("StoreKit 2 requires iOS 15 or later"))
      return
    }
    Task { @MainActor [weak self] in
      guard let self else {
        result(selfUnavailable())
        return
      }
      do {
        result(try await operation(coordinator()))
      } catch let error as StoreKit2BridgeError {
        result(error.flutterError)
      } catch {
        result(
          FlutterError(
            code: "storekit_failed",
            message: "StoreKit operation failed",
            details: nil
          )
        )
      }
    }
  }

  @available(iOS 15.0, *)
  @MainActor
  private func coordinator() -> StoreKit2Coordinator {
    if let value = coordinatorObject as? StoreKit2Coordinator {
      return value
    }
    let value = StoreKit2Coordinator(maximumJwsLength: Self.maximumJwsLength)
    coordinatorObject = value
    return value
  }

  private func productIdentifiers(from arguments: Any?) -> [String]? {
    guard
      let values = arguments as? [String: Any],
      let raw = values["productIds"] as? [Any],
      !raw.isEmpty,
      raw.count <= Self.maximumProductCount
    else { return nil }
    let productIds = raw.compactMap { boundedIdentifier($0) }
    guard
      productIds.count == raw.count,
      Set(productIds).count == productIds.count
    else { return nil }
    return productIds
  }

  private func boundedIdentifier(_ raw: Any?) -> String? {
    guard let value = raw as? String else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !normalized.isEmpty,
      normalized == value,
      normalized.count <= Self.maximumIdentifierLength,
      normalized.unicodeScalars.allSatisfy({ scalar in
        scalar.value >= 0x21 && scalar.value <= 0x7e
      })
    else { return nil }
    return normalized
  }

  private func invalidRequest(_ message: String) -> FlutterError {
    FlutterError(code: "invalid_request", message: message, details: nil)
  }

  private func unavailable(_ message: String) -> FlutterError {
    FlutterError(code: "unsupported_os", message: message, details: nil)
  }

  private func selfUnavailable() -> FlutterError {
    FlutterError(
      code: "native_unavailable",
      message: "StoreKit bridge is unavailable",
      details: nil
    )
  }
}

@available(iOS 15.0, *)
@MainActor
private final class StoreKit2Coordinator {
  private let maximumJwsLength: Int
  private var products: [Product.ID: Product] = [:]
  private var finishableTransactions: [UInt64: Transaction] = [:]
  private var updatesTask: Task<Void, Never>?

  init(maximumJwsLength: Int) {
    self.maximumJwsLength = maximumJwsLength
  }

  func startUpdates(
    onTransaction: @escaping @MainActor ([String: Any]) -> Void
  ) {
    guard updatesTask == nil else { return }
    updatesTask = Task { [weak self] in
      for await verification in Transaction.updates {
        guard let self else { return }
        do {
          let payload = try transactionPayload(
            verification,
            source: "updates"
          )
          onTransaction(payload)
        } catch {
          // A malformed or over-sized transaction cannot be forwarded to
          // Flutter. It deliberately remains unfinished for later recovery.
        }
      }
    }
  }

  func loadProducts(_ productIds: [String]) async throws -> [[String: Any]] {
    let loaded = try await Product.products(for: productIds)
    var response: [[String: Any]] = []
    for product in loaded where product.type == .consumable {
      products[product.id] = product
      response.append([
        "id": product.id,
        "displayName": product.displayName,
        "description": product.description,
        "displayPrice": product.displayPrice,
        "productType": "consumable",
      ])
    }
    return response.sorted {
      ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "")
    }
  }

  func purchase(
    productId: String,
    appAccountToken: UUID
  ) async throws -> [String: Any] {
    let product: Product
    if let cached = products[productId] {
      product = cached
    } else {
      let loaded = try await Product.products(for: [productId])
      guard
        let value = loaded.first(where: { $0.id == productId }),
        value.type == .consumable
      else {
        throw StoreKit2BridgeError.productNotFound
      }
      products[value.id] = value
      product = value
    }

    let result = try await product.purchase(
      options: [.appAccountToken(appAccountToken)]
    )
    switch result {
    case .success(let verification):
      return [
        "outcome": "transaction",
        "transaction": try transactionPayload(
          verification,
          source: "purchase"
        ),
      ]
    case .pending:
      return ["outcome": "pending"]
    case .userCancelled:
      return ["outcome": "user_cancelled"]
    @unknown default:
      return ["outcome": "failed"]
    }
  }

  func recoverUnfinished(
    synchronizeStore: Bool
  ) async throws -> [[String: Any]] {
    if synchronizeStore {
      try await AppStore.sync()
    }
    var response: [[String: Any]] = []
    for await verification in Transaction.unfinished {
      response.append(
        try transactionPayload(verification, source: "unfinished")
      )
    }
    return response
  }

  /// This is the only native location that completes a StoreKit transaction.
  /// Flutter reaches it only after the first-party backend acknowledges
  /// `DELIVERED` or `ALREADY_DELIVERED` with `finishAllowed=true`.
  func finish(transactionId: UInt64) async throws -> Bool {
    if let transaction = finishableTransactions[transactionId] {
      await transaction.finish()
      finishableTransactions.removeValue(forKey: transactionId)
      return true
    }
    for await verification in Transaction.unfinished {
      let transaction: Transaction
      switch verification {
      case .verified(let value):
        transaction = value
      case .unverified(let value, _):
        transaction = value
      }
      if transaction.id == transactionId {
        await transaction.finish()
        finishableTransactions.removeValue(forKey: transactionId)
        return true
      }
    }
    return false
  }

  private func transactionPayload(
    _ verification: VerificationResult<Transaction>,
    source: String
  ) throws -> [String: Any] {
    let transaction: Transaction
    let verificationState: String
    switch verification {
    case .verified(let value):
      transaction = value
      verificationState = "verified"
      finishableTransactions[value.id] = value
    case .unverified(let value, _):
      transaction = value
      verificationState = "unverified"
      // Local verification is diagnostic only. The backend independently
      // verifies the Apple-signed JWS; after a delivery ACK, the exact native
      // transaction may safely be completed even if this device reported an
      // unverified local result.
      finishableTransactions[value.id] = value
    }

    let signedTransaction = verification.jwsRepresentation
    guard
      !signedTransaction.isEmpty,
      signedTransaction.utf8.count <= maximumJwsLength
    else {
      throw StoreKit2BridgeError.invalidSignedTransaction
    }

    var payload: [String: Any] = [
      "transactionId": String(transaction.id),
      "originalTransactionId": String(transaction.originalID),
      "productId": transaction.productID,
      "purchaseDate": ISO8601DateFormatter().string(
        from: transaction.purchaseDate
      ),
      "signedTransaction": signedTransaction,
      "verification": verificationState,
      "source": source,
    ]
    if let appAccountToken = transaction.appAccountToken {
      payload["appAccountToken"] = appAccountToken.uuidString.lowercased()
    }
    return payload
  }
}

private enum StoreKit2BridgeError: Error {
  case productNotFound
  case invalidSignedTransaction

  var flutterError: FlutterError {
    switch self {
    case .productNotFound:
      return FlutterError(
        code: "product_not_found",
        message: "StoreKit product is unavailable",
        details: nil
      )
    case .invalidSignedTransaction:
      return FlutterError(
        code: "invalid_signed_transaction",
        message: "StoreKit transaction data is invalid",
        details: nil
      )
    }
  }
}
