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

		for inputItem in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
			for provider in inputItem.attachments ?? [] {
				for newItem in ArchivedDropItem.importData(providers: [provider], delegate: self, overrides: nil) {
					newItems.append(newItem)
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

		resetExtension()

		let error = NSError(domain: GladysErrorDomain, code: 84, userInfo: [ NSLocalizedDescriptionKey: statusLabel.text ?? "No further info" ])
		extensionContext?.cancelRequest(withError: error)
	}

	func itemIngested(item: ArchivedDropItem) {
		loadCount -= 1
		if loadCount == 0 {
			commit(uploadAfterSave: CloudManager.shareActionShouldUpload)
		}
	}

	private func commit(uploadAfterSave: Bool) {
		cancelButton.isEnabled = false
		statusLabel.text = "Indexing..."
		Model.reIndexWithoutLoading(items: newItems) {
			DispatchQueue.main.async { [weak self] in
				self?.save(uploadAfterSave: uploadAfterSave)
			}
		}
	}

	private func save(uploadAfterSave: Bool) {
		statusLabel.text = "Saving..."
		let newItemIds = newItems.map { $0.uuid.uuidString }
		CloudManager.shareActionIsActioningIds = uploadAfterSave ? newItemIds : []
		for item in newItems {
			if Model.drops.contains(item) {
				Model.commitExistingItemWithoutLoading(item)
			} else {
				Model.insertNewItemsWithoutLoading(items: [item], addToDrops: true)
			}
		}

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
		log("Action done")
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

	private func resetExtension() {
		firstAppearance = true
		newItems.removeAll()
		Model.reset()
	}

	@objc private func done() {
		resetExtension()
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
				for l in item.labels {
					labels.insert(l)
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
		for item in newItems where item.labels != newLabels {
			item.labels = newLabels
			item.markUpdated()
			changes = true
		}
		if changes {
			navigationItem.rightBarButtonItem = nil
			labelsButton.isHidden = true
			statusLabel.isHidden = false
			commit(uploadAfterSave: true)
		}
	}
}
