//
//  ActionRequestHandler.swift
//  GladysAction
//
//  Created by Paul Tsochantaris on 02/07/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class ActionRequestViewController: UIViewController {

	@IBOutlet private weak var statusLabel: UILabel!
	@IBOutlet private weak var cancelButton: UIBarButtonItem!
	@IBOutlet private weak var imageHeight: NSLayoutConstraint!
	@IBOutlet private weak var expandButton: UIButton!
	@IBOutlet private weak var image: UIImageView!
	@IBOutlet private weak var labelsButton: UIButton!
	@IBOutlet private weak var imageOffset: NSLayoutConstraint!

	private var loadCount = 0
	private var ingestOnWillAppear = true
	private var newItems = [ArchivedItem]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(itemIngested(_:)), name: .IngestComplete, object: nil)
        ingest()
    }

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
        if ingestOnWillAppear {
            ingest()
        }
    }
    
    private func ingest() {
        reset(ingestOnNextAppearance: false) // resets everything

        statusLabel.text = "Adding…"
        statusLabel.isHidden = false
		expandButton.isHidden = true
		loadCount = extensionContext?.inputItems.count ?? 0

		if loadCount == 0 {
			statusLabel.text = "There don't seem to be any importable items offered by this app."
			showDone()
			return
		}

		Model.reloadDataIfNeeded()
		
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
        expandButton.isHidden = true

		var inputItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []

		if inputItems.count == 2 {
			// Special Safari behaviour, adds weird 2nd URL, let's remove it
			var count = 0
			var hasSafariFlag = false
			var weirdIndex: Int?
			var index = 0
			for item in inputItems {
				if item.attachments?.count == 1, let provider = item.attachments?.first, provider.registeredTypeIdentifiers.count == 1, provider.registeredTypeIdentifiers.first == "public.url" {
					count += 1
					if item.userInfo?["supportsJavaScript"] as? Int == 1 {
						hasSafariFlag = true
					} else {
						weirdIndex = index
					}
				}
				index += 1
			}
			// If all are URLs, find the weird link, if any, and trim it
			if count == inputItems.count, hasSafariFlag, let weirdIndex = weirdIndex {
				inputItems.remove(at: weirdIndex)
			}
		}

		let providerList = inputItems.reduce([]) { list, inputItem -> [NSItemProvider] in
			if let attachments = inputItem.attachments {
				return list + attachments
			} else {
				return list
			}
		}

		var allDifferentTypes = true
		var typeSet = Set<String>()
		for p in providerList {
			let currentTypes = Set(p.registeredTypeIdentifiers)
			if typeSet.isDisjoint(with: currentTypes) {
				typeSet.formUnion(currentTypes)
			} else {
				allDifferentTypes = false
				break
			}
		}

		if allDifferentTypes { // posibly this is a composite item, leave it up to the user's settings
			for newItem in ArchivedItem.importData(providers: providerList, overrides: nil) {
				newItems.append(newItem)
			}
		} else { // list of items shares common types, let's assume they are multiple items per provider
			for provider in providerList {
				for newItem in ArchivedItem.importData(providers: [provider], overrides: nil) {
					newItems.append(newItem)
				}
			}
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

        newItems.forEach { $0.cancelIngest() }

        reset(ingestOnNextAppearance: true)

		let error = NSError(domain: GladysErrorDomain, code: 84, userInfo: [ NSLocalizedDescriptionKey: statusLabel.text ?? "No further info" ])
		extensionContext?.cancelRequest(withError: error)
	}

    @objc private func itemIngested(_ notification: Notification) {
        if Model.doneIngesting {
			commit(initialAdd: true)
		}
	}

	private func commit(initialAdd: Bool) {
		cancelButton.isEnabled = false
        statusLabel.text = "Saving…"

		for item in newItems {

			var change = false
			if item.labels != labelsToApply {
				item.labels = labelsToApply
				change = true
			}

			if item.note != noteToApply {
				item.note = noteToApply
				change = true
			}

			if !initialAdd && change {
				item.markUpdated()
			}
		}

		if initialAdd {
			Model.insertNewItemsWithoutLoading(items: newItems, addToDrops: true)
		} else {
			Model.commitExistingItemsWithoutLoading(newItems)
		}
        
		if PersistedOptions.setLabelsWhenActioning {
			statusLabel.isHidden = true
			labelsButton.isHidden = false
			showDone()
		} else {
			statusLabel.text = "Done"
			done()
		}
        
        log("Commit done")
	}

	private func showDone() {
		navigationItem.rightBarButtonItem = makeDoneButton(target: self, action: #selector(done))
	}

    private func reset(ingestOnNextAppearance: Bool) {
        ingestOnWillAppear = ingestOnNextAppearance
		newItems.removeAll()
        labelsToApply.removeAll()
		noteToApply = ""
		Model.reset()
	}

	@objc private func done() {
        reset(ingestOnNextAppearance: true)
        scheduleAppRefresh()
        
        self.extensionContext?.completeRequest(returningItems: nil) { _ in
            log("Dismissed")
            
        }
	}
    
	////////////////////// Labels

    private var labelsToApply = [String]()
    private var noteToApply = ""

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let destination = segue.destination as? LabelEditorController {
			if !newItems.isEmpty { // we're not in the process of adding
				Model.reloadDataIfNeeded()
			}
			destination.note = noteToApply
			destination.selectedLabels = labelsToApply
            destination.completion = { [weak self] newLabels, newNote in
                self?.apply(newLabels, newNote)
            }
		}
	}

	private func apply(_ newLabels: [String], _ newNote: String) {
		labelsToApply = newLabels
		noteToApply = newNote

		let changes = newItems.contains { $0.labels != newLabels || $0.note != newNote }
		if changes {
			navigationItem.rightBarButtonItem = nil
			labelsButton.isHidden = true
			statusLabel.isHidden = false
			Model.reloadDataIfNeeded()
			commit(initialAdd: false)
		}
	}
}
