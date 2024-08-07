import Foundation
import GladysCommon
import StoreKit

public extension SKProduct {
    var regularPrice: String? {
        priceFormatter.locale = priceLocale
        return priceFormatter.string(from: price)
    }
}

public final class TipJar: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    private let completion: ([SKProduct]?, Error?) -> Void

    #if canImport(AppKit)
        private static let identifiers: Set<String> = [
            "MAC_GLADYS_TIP_TIER_001",
            "MAC_GLADYS_TIP_TIER_002",
            "MAC_GLADYS_TIP_TIER_003",
            "MAC_GLADYS_TIP_TIER_004",
            "MAC_GLADYS_TIP_TIER_005"
        ]
    #else
        private static let identifiers: Set<String> = [
            "GLADYS_TIP_TIER_001",
            "GLADYS_TIP_TIER_002",
            "GLADYS_TIP_TIER_003",
            "GLADYS_TIP_TIER_004",
            "GLADYS_TIP_TIER_005"
        ]
    #endif

    public static func warmup() {
        SKProductsRequest(productIdentifiers: TipJar.identifiers).start()
    }

    public init(completion: @escaping ([SKProduct]?, Error?) -> Void) {
        self.completion = completion
        super.init()
        SKPaymentQueue.default().add(self)

        let r = SKProductsRequest(productIdentifiers: TipJar.identifiers)
        r.delegate = self
        r.start()
    }

    deinit {
        SKPaymentQueue.default().remove(self)
    }

    public func productsRequest(_: SKProductsRequest, didReceive response: SKProductsResponse) {
        let items = response.products.sorted { $0.productIdentifier.localizedCaseInsensitiveCompare($1.productIdentifier) == .orderedAscending }
        Task { @MainActor in
            completion(items, nil)
        }
    }

    public func request(_: SKRequest, didFailWithError error: Error) {
        log("Error fetching IAP items: \(error.localizedDescription)")
        Task { @MainActor in
            completion(nil, error)
        }
    }

    private var purchaseCompletion: ((Error?) -> Void)?
    public func requestItem(_ item: SKProduct) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            purchaseCompletion = { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            let payment = SKPayment(product: item)
            SKPaymentQueue.default().add(payment)
        }
    }

    public func paymentQueue(_: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task {
            for t in transactions {
                let prefix: String
                #if canImport(AppKit)
                    prefix = "MAC_GLADYS_TIP_TIER"
                #else
                    prefix = "GLADYS_TIP_TIER_"
                #endif
                if t.payment.productIdentifier.hasPrefix(prefix) {
                    switch t.transactionState {
                    case .failed:
                        SKPaymentQueue.default().finishTransaction(t)
                        let completion = purchaseCompletion
                        purchaseCompletion = nil
                        completion?(t.error)

                    case .purchased, .restored:
                        SKPaymentQueue.default().finishTransaction(t)
                        let completion = purchaseCompletion
                        purchaseCompletion = nil
                        completion?(nil)

                    case .deferred, .purchasing:
                        break

                    @unknown default:
                        break
                    }
                } else {
                    switch t.transactionState {
                    case .failed, .purchased, .restored:
                        SKPaymentQueue.default().finishTransaction(t)

                    case .deferred, .purchasing:
                        break

                    @unknown default:
                        break
                    }
                }
            }
        }
    }
}
