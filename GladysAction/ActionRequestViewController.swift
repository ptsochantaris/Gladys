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

		loadCount = extensionContext?.inputItems.count ?? 0

		if loadCount == 0 {
			statusLabel?.text = "There don't seem to be any items offered by this app."
			return
		}

		let newTotal = model.drops.count + loadCount
		if !infiniteMode && newTotal > nonInfiniteItemLimit {
			imageHeight.constant = 60
			imageCenter.constant = -110
			imageDistance.constant = 40
			expandButton.isHidden = false
			statusLabel?.text = "That operation would result in a total of \(newTotal) items, and Gladys will hold up \(nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time in-app purchase."
			return
		}

		var itemCount = 0
		for inputItem in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
			if let providers = inputItem.attachments as? [NSItemProvider] {
				itemCount += providers.count
				let newItem = ArchivedDropItem(providers: providers, delegate: self)
				model.drops.insert(newItem, at: 0)
			}
		}

		statusLabel?.text = "Adding \(itemCount) items..."
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
			model.save()
			extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
		}
	}

	func loadingProgress(sender: AnyObject) {}
}

