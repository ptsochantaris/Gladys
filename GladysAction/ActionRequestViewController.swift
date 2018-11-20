//
//  ActionRequestHandler.swift
//  GladysAction
//
//  Created by Paul Tsochantaris on 02/07/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

class ActionRequestViewController: UIViewController, ItemIngestionDelegate {

	@IBOutlet private weak var statusLabel: UILabel!
	@IBOutlet private weak var cancelButton: UIBarButtonItem!
	@IBOutlet private weak var imageHeight: NSLayoutConstraint!
	@IBOutlet private weak var expandButton: UIButton!
	@IBOutlet private weak var background: UIImageView!
	@IBOutlet private weak var image: UIImageView!
	@IBOutlet private weak var labelsButton: UIButton!
	@IBOutlet private weak var imageOffset: NSLayoutConstraint!

	private var loadCount = 0
	private var ingestCount = 0
	private var firstAppearance = true
	private var newItems = [ArchivedDropItem]()
	private var uploadObservation: NSKeyValueObservation?
	private var uploadProgress: Progress?

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if firstAppearance {
			firstAppearance = false
			// and proceed with setup
		} else {
			return
		}

		expandButton.isHidden = true
		loadCount = extensionContext?.inputItems.count ?? 0

		if loadCount == 0 {
			statusLabel.text = "There don't seem to be any items offered by this app."
			showDone()
			return
		}

		newItems.removeAll()
		Model.reset()
		Model.reloadDataIfNeeded()

		if Model.legacyMode {
			statusLabel.text = "Please run Gladys once after the update, the data store needs to be updated before adding new items through this extension."
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
			statusLabel.text = "That operation would result in a total of \(newTotal) items, and Gladys will hold up to \(nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time in-app purchase."
			return
		}

		labelsButton.isHidden = !PersistedOptions.setLabelsWhenActioning

		var providerList = [NSItemProvider]()
		for inputItem in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
			for provider in inputItem.attachments ?? [] {
				providerList.append(provider)
			}
		}

		var allDifferentTypes = true
		var typeSet = Set<String>()
		for p in providerList {
			let currentTypes = Set(p.registeredTypeIdentifiers)
			if typeSet.intersection(currentTypes).isEmpty {
				typeSet.formUnion(currentTypes)
			} else {
				allDifferentTypes = false
				break
			}
		}

		if allDifferentTypes { // posibly this is a composite item, leave it up to the user's settings
			for newItem in ArchivedDropItem.importData(providers: providerList, delegate: self, overrides: nil) {
				newItems.append(newItem)
			}
		} else { // list of items shares common types, let's assume they are multiple items per provider
			for provider in providerList {
				for newItem in ArchivedDropItem.importData(providers: [provider], delegate: self, overrides: nil) {
					newItems.append(newItem)
				}
			}
		}

		ingestCount = newItems.count

		if PersistedOptions.darkMode {
			image.alpha = 0.7
			background.image = nil
			if let navigationBar = navigationController?.navigationBar {
				navigationBar.barTintColor = .darkGray
				navigationBar.tintColor = .lightGray
			}
			statusLabel.textColor = .lightGray
			view.tintColor = .lightGray
			view.backgroundColor = .black
			expandButton.setTitleColor(.white, for: .normal)
			labelsButton.setTitleColor(.white, for: .normal)
		}
    }

	@IBAction private func expandSelected(_ sender: UIButton) {

		let newTotal = Model.drops.count + loadCount
		let url = URL(string: "gladys://in-app-purchase/\(newTotal)")!

		cancelRequested(cancelButton) // warning: resets model counts from above!

		let selector = sel_registerName("openURL:")
		var responder = self as UIResponder?
		while let r = responder, !r.responds(to: selector) {
			responder = r.next
		}
		_ = responder?.perform(selector, with: url)
	}

	@IBAction private func cancelRequested(_ sender: UIBarButtonItem) {

		for loadingItem in newItems {
			loadingItem.delegate = nil
			loadingItem.cancelIngest()
		}

		shutdownExtension()

		let error = NSError(domain: GladysErrorDomain, code: 84, userInfo: [ NSLocalizedDescriptionKey: statusLabel.text ?? "No further info" ])
		extensionContext?.cancelRequest(withError: error)
	}

	func itemIngested(item: ArchivedDropItem) {
		ingestCount -= 1
		if ingestCount == 0 {
			commit()
		}
	}

	private func commit() {
		cancelButton.isEnabled = false
		statusLabel.text = "Indexing..."
		Model.reIndexWithoutLoading(items: newItems) {
			DispatchQueue.main.async { [weak self] in
				self?.save()
			}
		}
	}

	private func save() {
		statusLabel.text = "Saving..."
		let uploadAfterSave = CloudManager.shareActionShouldUpload
		let newItemIds = newItems.map { $0.uuid.uuidString }
		CloudManager.shareActionIsActioningIds = uploadAfterSave ? newItemIds : []
		var itemsToCommit = [ArchivedDropItem]()
		var itemsToInsert = [ArchivedDropItem]()
		for item in newItems {
			if Model.drops.contains(item) {
				itemsToCommit.append(item)
			} else {
				itemsToInsert.append(item)
			}
		}
		Model.commitExistingItemsWithoutLoading(itemsToCommit)
		Model.insertNewItemsWithoutLoading(items: itemsToInsert, addToDrops: true)

		if !uploadAfterSave {
			sharingDone(error: nil)
			return
		}

		uploadProgress = CloudManager.sendUpdatesUp { [weak self] error in // will callback immediately if sync is off
			self?.sharingDone(error: error)
		}

		if let p = uploadProgress {
			statusLabel.text = "Uploading..."
			uploadObservation = p.observe(\Progress.completedUnitCount) { [weak self] progress, change in
				let complete = Int((progress.fractionCompleted * 100).rounded())
				self?.statusLabel.text = "\(complete)% Uploaded"
			}
		}
	}

	private func sharingDone(error: Error?) {
		uploadObservation = nil
		uploadProgress = nil
		if let error = error {
			log("Error while sending up items from extension: \(error.finalDescription)")
		}
		log("Sharing done")
		if PersistedOptions.setLabelsWhenActioning {
			statusLabel.isHidden = true
			labelsButton.isHidden = false
			showDone()
		} else {
			statusLabel.text = "Done"
			done()
		}
	}

	private func showDone() {
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
	}

	private func shutdownExtension() {
		firstAppearance = true
		newItems.removeAll()
		Model.reset()
	}

	@objc private func done() {
		shutdownExtension()
		DispatchQueue.main.async { [weak self] in
			self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
		}
	}

	////////////////////// Labels

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let destination = segue.destination as? LabelEditorController {
			Model.reloadDataIfNeeded()
			var labels = Set<String>()
			for item in newItems {
				labels.formUnion(item.labels)
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
		for item in newItems where item.labels != newLabels {
			item.labels = newLabels
			item.markUpdated()
			changes = true
		}
		if changes {
			navigationItem.rightBarButtonItem = nil
			labelsButton.isHidden = true
			statusLabel.isHidden = false
			commit()
		}
	}
}
