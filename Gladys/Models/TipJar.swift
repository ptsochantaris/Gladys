//
//  IAPManager.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import StoreKit

extension SKProduct {

    var regularPrice: String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = self.priceLocale
        return formatter.string(from: self.price)
    }
}

final class TipJar: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    
    private let completion: ([SKProduct]?, Error?) -> Void
    #if MAC
    var aboutWindow: NSWindow?
    #endif

    init(completion: @escaping ([SKProduct]?, Error?) -> Void) {
        self.completion = completion
        super.init()
        SKPaymentQueue.default().add(self)
        
        let identifiers: Set<String>
        #if MAC
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

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async { [weak self] in
            let items = response.products.sorted { $0.productIdentifier.localizedCaseInsensitiveCompare($1.productIdentifier) == .orderedAscending }
            self?.completion(items, nil)
        }
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        log("Error fetching IAP items: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.completion(nil, error)
        }
    }
    
    private var purchaseCompletion: (() -> Void)?
    func requestItem(_ item: SKProduct, completion: @escaping () -> Void) {
        purchaseCompletion = completion
        let payment = SKPayment(product: item)
        SKPaymentQueue.default().add(payment)
    }

    private func displaySuccess() {
        let completion = purchaseCompletion
        purchaseCompletion = nil
        #if MAC
        genericAlert(title: "Thank you for supporting Gladys!",
                     message: "Thank you so much for your support, it means a lot, and it ensures that Gladys will keep receiving improvements and features in the future.",
                     windowOverride: aboutWindow,
                     completion: completion)
        #else
        genericAlert(title: "Thank you for supporting Gladys!",
                     message: "Thank you so much for your support, it means a lot, and it ensures that Gladys will keep receiving improvements and features in the future.",
                     completion: completion)
        #endif
    }
    
    private func displayFailure(error: Error?) {
        let completion = purchaseCompletion
        purchaseCompletion = nil
        #if MAC
        genericAlert(title: "There was an error completing this operation",
                     message: error?.localizedDescription,
                     windowOverride: aboutWindow,
                     completion: completion)
        #else
        genericAlert(title: "There was an error completing this operation",
                     message: error?.localizedDescription,
                     completion: completion)
        #endif
    }

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        DispatchQueue.main.async { [weak self] in
            for t in transactions {
                let prefix: String
                #if MAC
                prefix = "MAC_GLADYS_TIP_TIER"
                #else
                prefix = "GLADYS_TIP_TIER_"
                #endif
                if t.payment.productIdentifier.hasPrefix(prefix) {
                    switch t.transactionState {
                    case .failed:
                        SKPaymentQueue.default().finishTransaction(t)
                        self?.displayFailure(error: t.error)
                    case .purchased, .restored:
                        SKPaymentQueue.default().finishTransaction(t)
                        self?.displaySuccess()
                    case .purchasing, .deferred:
                        break
                    @unknown default:
                        break
                    }
                } else {
                    switch t.transactionState {
                    case .purchased, .restored, .failed:
                        SKPaymentQueue.default().finishTransaction(t)
                    case .purchasing, .deferred:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }
    }
}
