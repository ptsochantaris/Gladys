//
//  IAPManager.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import StoreKit

final class IAPManager: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {

	static var shared = IAPManager()

	private var iapFetchCallbackCount: Int?
	private var infiniteModeItem: SKProduct?

	#if os(iOS)
	static private let id = "INFINITE"
	#else
	static private let id = "MACINFINITE"
	#endif

	func start() {
		SKPaymentQueue.default().add(self)
		fetch()
	}

	func stop() {
		SKPaymentQueue.default().remove(self)
	}

	private func fetch() {
		if !infiniteMode {
			let r = SKProductsRequest(productIdentifiers: [IAPManager.id])
			r.delegate = self
			r.start()
		}
	}

	func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
		infiniteModeItem = response.products.first
		DispatchQueue.main.async { [weak self] in
			self?.iapFetchCompletion()
		}
	}

	func request(_ request: SKRequest, didFailWithError error: Error) {
		log("Error fetching IAP items: \(error.finalDescription)")
		DispatchQueue.main.async { [weak self] in
			self?.iapFetchCompletion()
		}
	}

	private func iapFetchCompletion() {
		if let c = iapFetchCallbackCount {
			iapFetchCallbackCount = nil
			displayRequest(newTotal: c)
		}
	}

	func displayRequest(newTotal: Int) {

		guard infiniteMode == false else { return }

		let title = "Gladys Unlimited"

		guard let infiniteModeItem = infiniteModeItem else {
			let message: String
			if newTotal == -1 {
				message = "We cannot seem to fetch the in-app purchase information at this time. Please check your Internet connection and try again in a moment."
			} else {
				message = "That operation would result in a total of \(newTotal) items, and Gladys will hold up to \(nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time in-app purchase.\n\nWe cannot seem to fetch the in-app purchase information at this time. Please check your internet connection and try again in a moment."
			}

            showIAPPrompt(title: title,
                          subtitle: message,
                          actionTitle: "Try Again",
                          actionAction: { [weak self] in
                            self?.iapFetchCallbackCount = newTotal
                            self?.fetch()
                }, cancelTitle: "Later")

			fetch()
			return
		}

		let f = NumberFormatter()
		f.numberStyle = .currency
		f.locale = infiniteModeItem.priceLocale
		let infiniteModeItemPrice = f.string(from: infiniteModeItem.price)!
		let message: String
		if newTotal == -1 {
			message = "You can expand Gladys to hold unlimited items with a one-time purchase of \(infiniteModeItemPrice)"
		} else {
			message = "That operation would result in a total of \(newTotal) items, and Gladys will hold up to \(nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or expand Gladys to hold unlimited items with a one-time purchase of \(infiniteModeItemPrice)"
		}

		let cancelTitle = newTotal == -1 ? "Cancel" : "Never mind, I'll delete old stuff"

		#if os(iOS)
		let os = "iOS"
		#else
		let os = "Mac"
		#endif
        showIAPPrompt(title: title,
                      subtitle: message,
                      actionTitle: "Restore previous \(os) purchase",
            actionAction: {
                SKPaymentQueue.default().restoreCompletedTransactions()
		}, destructiveTitle: "Buy for \(infiniteModeItemPrice)", destructiveAction: {
			let payment = SKPayment(product: infiniteModeItem)
			SKPaymentQueue.default().add(payment)
		}, cancelTitle: cancelTitle)
	}

	private func displaySuccess() {
		if infiniteMode {
			genericAlert(title: "You can now add unlimited items!",
						 message: "Thank you for supporting Gladys.")
		} else {
			genericAlert(title: "Something went wrong with the purchase on the App Store side",
						 message: "Please try again in a moment. You will not be charged twice if your purchase has already gone through.")
		}
	}

	func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
		DispatchQueue.main.async {
			if !infiniteMode {
				genericAlert(title: "Purchase could not be restored",
							 message: "Are you sure you purchased this from the App Store account that you are currently using?")
			}
		}
	}

	func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
		DispatchQueue.main.async {
			genericAlert(title: "There was an error restoring your purchase",
						 message: error.finalDescription)
		}
	}

	func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
		DispatchQueue.main.async { [weak self] in
			for t in transactions.filter({ $0.payment.productIdentifier == IAPManager.id }) {
				switch t.transactionState {
				case .failed:
					SKPaymentQueue.default().finishTransaction(t)
					genericAlert(title: "There was an error completing this purchase",
								 message: t.error?.finalDescription)
				case .purchased, .restored:
					SKPaymentQueue.default().finishTransaction(t)
					reVerifyInfiniteMode()
					self?.displaySuccess()
				case .purchasing, .deferred:
					break
				@unknown default:
					break
				}
			}
		}
	}

	func checkInfiniteMode(for insertCount: Int) -> Bool {
		if !infiniteMode && insertCount > 0 {
			let newTotal = Model.drops.count + insertCount
			if newTotal > nonInfiniteItemLimit {
				IAPManager.shared.displayRequest(newTotal: newTotal)
				return true
			}
		}
		return false
	}
    
    #if MAINAPP
    private func showIAPPrompt(title: String, subtitle: String,
                               actionTitle: String? = nil, actionAction: (() -> Void)? = nil,
                               destructiveTitle: String? = nil, destructiveAction: (() -> Void)? = nil,
                               cancelTitle: String? = nil) {

        NotificationCenter.default.post(name: .DismissPopoversRequest, object: nil)
        NotificationCenter.default.post(name: .ResetSearchRequest, object: nil)

        let a = UIAlertController(title: title, message: subtitle, preferredStyle: .alert)
        if let destructiveTitle = destructiveTitle {
            a.addAction(UIAlertAction(title: destructiveTitle, style: .destructive) { _ in destructiveAction?() })
        }
        if let actionTitle = actionTitle {
            a.addAction(UIAlertAction(title: actionTitle, style: .default) { _ in actionAction?() })
        }
        if let cancelTitle = cancelTitle {
            a.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
        }

        let scene = currentWindow?.windowScene
        let request = UIRequest(vc: a, sourceView: nil, sourceRect: nil, sourceButton: nil, pushInsteadOfPresent: false, sourceScene: scene)
        NotificationCenter.default.post(name: .UIRequest, object: request)
    }
    #endif

    #if MAC
    func showIAPPrompt(title: String, subtitle: String,
                       actionTitle: String? = nil, actionAction: (() -> Void)? = nil,
                       destructiveTitle: String? = nil, destructiveAction: (() -> Void)? = nil,
                       cancelTitle: String? = nil) {

        assert(Thread.isMainThread)

        if Model.sharedFilter.isFiltering {
            ViewController.shared.resetSearch(andLabels: true)
        }

        let a = NSAlert()
        a.messageText = title
        a.informativeText = subtitle
        if let cancelTitle = cancelTitle {
            a.addButton(withTitle: cancelTitle)
        }
        if let actionTitle = actionTitle {
            a.addButton(withTitle: actionTitle)
        }
        if let destructiveTitle = destructiveTitle {
            a.addButton(withTitle: destructiveTitle)
        }
        a.beginSheetModal(for: ViewController.shared.view.window!) { response in
            switch response.rawValue {
            case 1001:
                actionAction?()
            case 1002:
                destructiveAction?()
            default:
                break
            }
        }
    }
    #endif
}
