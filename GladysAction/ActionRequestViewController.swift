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
	private var firstAppearance = true

	@IBOutlet private weak var statusLabel: UILabel?
	@IBOutlet private weak var cancelButton: UIBarButtonItem?
	@IBOutlet private weak var imageHeight: NSLayoutConstraint!
	@IBOutlet private weak var expandButton: UIButton!
	@IBOutlet private weak var background: UIImageView!
	@IBOutlet private weak var image: UIImageView!
	@IBOutlet private weak var labelsButton: UIButton!
	@IBOutlet private weak var imageOffset: NSLayoutConstraint!

	private var newItemIds = [String]()

	override func viewDidLoad() {
		super.viewDidLoad()
		expandButton.isHidden = true
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if !firstAppearance {
			return
		}
		firstAppearance = false

		loadCount = extensionContext?.inputItems.count ?? 0

		if loadCount == 0 {
			statusLabel?.text = "There don't seem to be any items offered by this app."
			return
		}

		Model.reset()
		Model.reloadDataIfNeeded()

		if Model.legacyMode {
			statusLabel?.text = "Please run Gladys once after the update, the data store needs to be updated before adding new items through this extension."
			return
		}
		
		let newTotal = Model.drops.count + loadCount
		if !infiniteMode && newTotal > nonInfiniteItemLimit {
			// ensure the app wasn't just registered, just in case, before we warn the user
			reVerifyInfiniteMode()
		}

		if !infiniteMode && newTotal > nonInfiniteItemLimit {
			imageHeight.constant = 60
			imageOffset.constant = -140
			labelsButton.isHidden = true
			expandButton.isHidden = false
			statusLabel?.text = "That operation would result in a total of \(newTotal) items, and Gladys will hold up to \(nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time in-app purchase."
			return
		}

		labelsButton.isHidden = !PersistedOptions.setLabelsWhenActioning

		for inputItem in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
			if let providers = inputItem.attachments as? [NSItemProvider] {
				for newItem in ArchivedDropItem.importData(providers: providers, delegate: self, overrides: nil) {
					Model.drops.insert(newItem, at: 0)
					newItemIds.append(newItem.uuid.uuidString)
				}
			}
		}

		if PersistedOptions.darkMode {
			image.alpha = 0.7
			background.image = nil
			if let navigationBar = navigationController?.navigationBar {
				navigationBar.barTintColor = .darkGray
				navigationBar.tintColor = .lightGray
			}
			statusLabel?.textColor = .lightGray
			view.tintColor = .lightGray
			view.backgroundColor = .black
			expandButton.setTitleColor(.white, for: .normal)
			labelsButton.setTitleColor(.white, for: .normal)
		}
    }

	@IBAction private func expandSelected(_ sender: UIButton) {

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

	@IBAction private func cancelRequested(_ sender: UIBarButtonItem) {

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
			commit()
		}
	}

	private func commit() {
		statusLabel?.text = "Indexing..."
		Model.searchableIndex(CSSearchableIndex.default(), reindexSearchableItemsWithIdentifiers: newItemIds) {
			DispatchQueue.main.async {
				self.statusLabel?.text = "Saving..."
				CloudManager.shareActionIsActioningIds = CloudManager.shareActionShouldUpload ? self.newItemIds : []
				Model.save()
			}
		}
		Model.queueNextSaveCallback { [weak self] in
			self?.postSave()
		}
	}

	private func postSave() {
		if !CloudManager.shareActionShouldUpload {
			sharingDone(error: nil)
			return
		}
		uploadProgress = CloudManager.sendUpdatesUp { error in // will call back immediately if sync is off
			self.sharingDone(error: error)
		}
		if let p = uploadProgress {
			statusLabel?.text = "Uploading..."
			uploadObservation = p.observe(\Progress.completedUnitCount) { [weak self] progress, change in
				let complete = Int((progress.fractionCompleted * 100).rounded())
				self?.statusLabel?.text = "\(complete)% Uploaded"
			}
		}
	}

	private func sharingDone(error: Error?) {
		uploadObservation = nil
		uploadProgress = nil
		if let error = error {
			log("Error while sending up items from extension: \(error.finalDescription)")
		}
		log("Action done")
		if PersistedOptions.setLabelsWhenActioning {
			statusLabel?.isHidden = true
			labelsButton.isHidden = false
			navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
		} else {
			statusLabel?.text = "Done"
			done()
		}
	}

	@objc private func done() {
		DispatchQueue.main.async {
			self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
		}
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let destination = segue.destination as? LabelEditorController {
			Model.reloadDataIfNeeded()
			var labels = Set<String>()
			for uuid in newItemIds {
				if let item = Model.item(uuid: uuid) {
					for l in item.labels {
						labels.insert(l)
					}
				}
			}
			destination.selectedLabels = Array(labels)
			destination.completion = { [weak self] newLabels in
				self?.applyNewLabels(newLabels)
			}
		}
	}

	private func applyNewLabels(_ newLabels: [String]) {
		Model.reloadDataIfNeeded()
		var changes = false
		for uuid in newItemIds {
			if let item = Model.item(uuid: uuid), item.labels != newLabels {
				item.labels = newLabels
				item.markUpdated()
				changes = true
			}
		}
		if changes {
			navigationItem.rightBarButtonItem = nil
			labelsButton.isHidden = true
			statusLabel?.isHidden = false
			commit()
		}
	}
}
