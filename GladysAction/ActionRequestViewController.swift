//
//  ActionRequestHandler.swift
//  GladysAction
//
//  Created by Paul Tsochantaris on 02/07/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CoreSpotlight

class ActionRequestViewController: UIViewController, LoadCompletionDelegate {

	private var loadCount = 0

	@IBOutlet weak var statusLabel: UILabel?
	@IBOutlet weak var cancelButton: UIBarButtonItem?
	@IBOutlet weak var imageHeight: NSLayoutConstraint!
	@IBOutlet weak var imageCenter: NSLayoutConstraint!
	@IBOutlet weak var imageDistance: NSLayoutConstraint!
	@IBOutlet weak var expandButton: UIButton!

	private var newItemIds = [String]()

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		loadCount = extensionContext?.inputItems.count ?? 0

		if loadCount == 0 {
			statusLabel?.text = "There don't seem to be any items offered by this app."
			return
		}

		Model.reset()
		Model.reloadDataIfNeeded()
		
		let newTotal = Model.drops.count + loadCount
		if !infiniteMode && newTotal > nonInfiniteItemLimit {
			imageHeight.constant = 60
			imageCenter.constant = -110
			imageDistance.constant = 40
			expandButton.isHidden = false
			statusLabel?.text = "That operation would result in a total of \(newTotal) items, and Gladys will hold up to \(nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time in-app purchase."
			return
		}

		var itemCount = 0
		for inputItem in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
			if let providers = inputItem.attachments as? [NSItemProvider] {
				itemCount += providers.count
				for newItem in ArchivedDropItem.importData(providers: providers, delegate: self, overrideName: nil) {
					Model.drops.insert(newItem, at: 0)
					newItemIds.append(newItem.uuid.uuidString)
				}
			}
		}

		if itemCount > 1 {
			statusLabel?.text = "Adding \(itemCount) items..."
		} else {
			statusLabel?.text = "Adding item..."
		}
    }

	@IBAction func expandSelected(_ sender: UIButton) {

		cancelRequested(cancelButton!)

		let newTotal = Model.drops.count + loadCount
		let url = URL(string: "gladys://in-app-purchase/\(newTotal)")!

		let selector = sel_registerName("openURL:")
		var responder = self as UIResponder?
		while let r = responder, !r.responds(to: selector) {
			responder = r.next
		}
		_ = responder?.perform(selector, with: url)
	}

	@IBAction func cancelRequested(_ sender: UIBarButtonItem) {

		let loadingItems = Model.drops.filter { $0.loadingProgress != nil }
		for loadingItem in loadingItems {
			loadingItem.delegate = nil
			loadingItem.cancelIngest()
		}
		Model.drops = Model.drops.filter({ i -> Bool in
			!loadingItems.contains { $0.uuid == i.uuid }
		})

		let error = NSError(domain: "build.bru.Gladys.error", code: 84, userInfo: [ NSLocalizedDescriptionKey: statusLabel?.text ?? "No further info" ])
		extensionContext?.cancelRequest(withError: error)
	}

	private var uploadObservation: NSKeyValueObservation?
	private var uploadProgress: Progress?

	func loadCompleted(sender: AnyObject) {
		loadCount -= 1
		if loadCount == 0 {
			cancelButton?.isEnabled = false

			statusLabel?.text = "Indexing..."
			Model.searchableIndex(CSSearchableIndex.default(), reindexSearchableItemsWithIdentifiers: newItemIds) {
				DispatchQueue.main.async {
					self.statusLabel?.text = "Saving..."
					CloudManager.shareActionIsActioningIds = CloudManager.shareActionShouldUpload ? self.newItemIds : []
					Model.save()
				}
			}
			Model.queueNextSaveCallback {
				if !CloudManager.shareActionShouldUpload {
					self.sharingDone(error: nil)
					return
				}
				self.uploadProgress = CloudManager.sendUpdatesUp { error in // will call back immediately if sync is off
					self.sharingDone(error: error)
				}
				if let p = self.uploadProgress {
					self.statusLabel?.text = "Uploading..."
					self.uploadObservation = p.observe(\Progress.completedUnitCount) { progress, change in
						let complete = Int((progress.fractionCompleted * 100).rounded())
						let line = "\(complete)% Uploaded"
						self.statusLabel?.text = line
					}
				}
			}
		}
	}

	private func sharingDone(error: Error?) {
		self.uploadObservation = nil
		self.uploadProgress = nil
		self.statusLabel?.text = "Done"
		if let error = error {
			log("Error while sending up items from extension: \(error.finalDescription)")
		}
		log("Action done")
		DispatchQueue.main.async {
			self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
		}
	}
}

