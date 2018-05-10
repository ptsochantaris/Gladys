//
//  IAPManager.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import StoreKit

class IAPManager: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {

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

			ViewController.shared.showIAPPrompt(title: title,
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

		ViewController.shared.showIAPPrompt(title: title,
											subtitle: message,
											actionTitle: "Restore previous purchase",
											actionAction: {
												SKPaymentQueue.default().restoreCompletedTransactions()
		}, destructiveTitle: "Buy for \(infiniteModeItemPrice)", destructiveAction: {
			let payment = SKPayment(product: infiniteModeItem)
			SKPaymentQueue.default().add(payment)
		}, cancelTitle: cancelTitle)
	}

	private func displaySuccess() {
		genericAlert(title: "You can now add unlimited items!",
					 message: "Thank you for supporting Gladys!",
					 on: ViewController.shared)
	}

	func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
		DispatchQueue.main.async {
			if !infiniteMode {
				genericAlert(title: "Purchase could not be restored",
							 message: "Are you sure you purchased this from the App Store account that you are currently using?",
							 on: ViewController.shared)
			}
		}
	}

	func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
		DispatchQueue.main.async {
			genericAlert(title: "There was an error restoring your purchase",
						 message: error.finalDescription,
						 on: ViewController.shared)
		}
	}

	func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
		DispatchQueue.main.async { [weak self] in
			for t in transactions.filter({ $0.payment.productIdentifier == IAPManager.id }) {
				switch t.transactionState {
				case .failed:
					SKPaymentQueue.default().finishTransaction(t)
					genericAlert(title: "There was an error completing this purchase",
								 message: t.error?.finalDescription,
								 on: ViewController.shared)
				case .purchased, .restored:
					SKPaymentQueue.default().finishTransaction(t)
					reVerifyInfiniteMode()
					self?.displaySuccess()
				case .purchasing, .deferred:
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
}
