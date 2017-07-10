//
//  ActionRequestHandler.swift
//  GladysAction
//
//  Created by Paul Tsochantaris on 02/07/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

class ActionRequestViewController: UIViewController, LoadCompletionDelegate {

	private var loadCount = 0
	private let model = Model()

	@IBOutlet var statusLabel: UILabel?
	@IBOutlet var cancelButton: UIBarButtonItem?
	@IBOutlet weak var imageHeight: NSLayoutConstraint!
	@IBOutlet weak var imageCenter: NSLayoutConstraint!
	@IBOutlet weak var imageDistance: NSLayoutConstraint!
	@IBOutlet weak var expandButton: UIButton!

	override func viewDidLoad() {

		for inputItem in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
			loadCount += inputItem.attachments?.count ?? 0
		}

		if loadCount == 0 {
			statusLabel?.text = "There don't seem to be any items offered by this app."
			return
		}

		let newTotal = model.drops.count + loadCount
		if !model.infiniteMode && newTotal > model.nonInfiniteItemLimit {
			imageHeight.constant = 60
			imageCenter.constant = -110
			imageDistance.constant = 40
			expandButton.isHidden = false
			statusLabel?.text = "That operation would result in a total of \(newTotal) items, and Gladys will hold up \(model.nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time in-app purchase."
			return
		}

		statusLabel?.text = "Adding \(loadCount) items..."

		for inputItem in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
			for provider in inputItem.attachments as? [NSItemProvider] ?? [] {
				let newItem = ArchivedDropItem(provider: provider, delegate: self)
				model.drops.insert(newItem, at: 0)
			}
		}
    }

	@IBAction func expandSelected(_ sender: UIButton) {

		cancelRequested(cancelButton!)

		let newTotal = model.drops.count + loadCount
		let url = URL(string: "gladys://in-app-purchase/\(newTotal)")!

		let selector = sel_registerName("openURL:")
		var responder = self as UIResponder?
		while let r = responder, !r.responds(to: selector) {
			responder = r.next
		}
		_ = responder?.perform(selector, with: url)
	}

	@IBAction func cancelRequested(_ sender: UIBarButtonItem) {

		let loadingItems = model.drops.filter({ $0.isLoading })
		for loadingItem in loadingItems {
			loadingItem.delegate = nil
			loadingItem.cancelIngest()
		}
		model.drops = model.drops.filter({ i -> Bool in
			loadingItems.contains { $0 === i }
		})

		let error = NSError(domain: "build.bru.Gladys.error", code: 84, userInfo: [ NSLocalizedDescriptionKey: statusLabel?.text ?? "No further info" ])
		extensionContext?.cancelRequest(withError: error)
	}

	func loadCompleted(sender: AnyObject, success: Bool) {
		loadCount -= 1
		if loadCount == 0 {
			statusLabel?.text = "Saving..."
			cancelButton?.isEnabled = false
			model.needsSave = true
			extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
		}
	}

	func loadingProgress(sender: AnyObject) {}
}

