import Foundation
import GladysCommon
import StoreKit

public extension SKProduct {
    var regularPrice: String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        return formatter.string(from: price)
    }
}

public final class TipJar: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    private let completion: ([SKProduct]?, Error?) -> Void
    #if os(macOS)
        public var aboutWindow: NSWindow?
    #endif

    public init(completion: @escaping ([SKProduct]?, Error?) -> Void) {
        self.completion = completion
        super.init()
        SKPaymentQueue.default().add(self)

        let identifiers: Set<String>
        #if os(macOS)
            identifiers = [
                "MAC_GLADYS_TIP_TIER_001",
                "MAC_GLADYS_TIP_TIER_002",
                "MAC_GLADYS_TIP_TIER_003",
                "MAC_GLADYS_TIP_TIER_004",
                "MAC_GLADYS_TIP_TIER_005"
            ]
        #else
            identifiers = [
                "GLADYS_TIP_TIER_001",
                "GLADYS_TIP_TIER_002",
                "GLADYS_TIP_TIER_003",
                "GLADYS_TIP_TIER_004",
                "GLADYS_TIP_TIER_005"
            ]
        #endif

        let r = SKProductsRequest(productIdentifiers: identifiers)
        r.delegate = self
        r.start()
    }

    deinit {
        SKPaymentQueue.default().remove(self)
    }

    public func productsRequest(_: SKProductsRequest, didReceive response: SKProductsResponse) {
        Task { @MainActor in
            let items = response.products.sorted { $0.productIdentifier.localizedCaseInsensitiveCompare($1.productIdentifier) == .orderedAscending }
            completion(items, nil)
        }
    }

    public func request(_: SKRequest, didFailWithError error: Error) {
        log("Error fetching IAP items: \(error.localizedDescription)")
        Task { @MainActor in
            completion(nil, error)
        }
    }

    private var purchaseCompletion: (() -> Void)?
    public func requestItem(_ item: SKProduct, completion: @escaping () -> Void) {
        purchaseCompletion = completion
        let payment = SKPayment(product: item)
        SKPaymentQueue.default().add(payment)
    }

    @MainActor
    private func displaySuccess() async {
        let completion = purchaseCompletion
        purchaseCompletion = nil
        #if os(macOS)
            await genericAlert(title: "Thank you for supporting Gladys!",
                               message: "Thank you so much for your support, it means a lot, and it ensures that Gladys will keep receiving improvements and features in the future.",
                               windowOverride: aboutWindow)
        #else
            await genericAlert(title: "Thank you for supporting Gladys!",
                               message: "Thank you so much for your support, it means a lot, and it ensures that Gladys will keep receiving improvements and features in the future.")
        #endif
        completion?()
    }

    @MainActor
    private func displayFailure(error: Error?) async {
        let completion = purchaseCompletion
        purchaseCompletion = nil
        #if os(macOS)
            await genericAlert(title: "There was an error completing this operation",
                               message: error?.localizedDescription,
                               windowOverride: aboutWindow)
        #else
            await genericAlert(title: "There was an error completing this operation",
                               message: error?.localizedDescription)
        #endif
        completion?()
    }

    public func paymentQueue(_: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task {
            for t in transactions {
                let prefix: String
                #if os(macOS)
                    prefix = "MAC_GLADYS_TIP_TIER"
                #else
                    prefix = "GLADYS_TIP_TIER_"
                #endif
                if t.payment.productIdentifier.hasPrefix(prefix) {
                    switch t.transactionState {
                    case .failed:
                        SKPaymentQueue.default().finishTransaction(t)
                        await displayFailure(error: t.error)
                    case .purchased, .restored:
                        SKPaymentQueue.default().finishTransaction(t)
                        await displaySuccess()
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
