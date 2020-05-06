//
//  ActionRequestHandler.swift
//  GladysAction
//
//  Created by Paul Tsochantaris on 02/07/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

extension Notification.Name {
    static let DoneSelected = Notification.Name("DoneSelected")
}

final class ActionRequestViewController: UIViewController {

	@IBOutlet private weak var statusLabel: UILabel!
	@IBOutlet private weak var cancelButton: UIBarButtonItem!
	@IBOutlet private weak var imageHeight: NSLayoutConstraint!
	@IBOutlet private weak var expandButton: UIButton!
	@IBOutlet private weak var image: UIImageView!
	@IBOutlet private weak var labelsButton: UIButton!
	@IBOutlet private weak var imageOffset: NSLayoutConstraint!
    @IBOutlet private weak var spinner: UIActivityIndicatorView!
    @IBOutlet private weak var check: UIImageView!
    
	private var loadCount = 0
	private var ingestOnWillAppear = true
	private var newItems = [ArchivedItem]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(itemIngested(_:)), name: .IngestComplete, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(done), name: .DoneSelected, object: nil)
        ingest()
    }

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
        
        if ingestOnWillAppear {
            ingest()
        }
    }
    
    private var newTotal: Int {
        return Model.countSavedItemsWithoutLoading() + loadCount
    }
    
    private func error(text: String) {
        statusLabel.isHidden = false
        statusLabel.text = text
        spinner.stopAnimating()
    }
    
    private func ingest() {
        reset(ingestOnNextAppearance: false) // resets everything

        showBusy(true)
		loadCount = extensionContext?.inputItems.count ?? 0

		if loadCount == 0 {
            error(text: "There don't seem to be any importable items offered by this app.")
			return
		}
		
		if !infiniteMode && newTotal > nonInfiniteItemLimit {
			// ensure the app wasn't just registered, just in case, before we warn the user
			reVerifyInfiniteMode()
		}

		if !infiniteMode && newTotal > nonInfiniteItemLimit {
			imageHeight.constant = 60
			imageOffset.constant = -140
			labelsButton.isHidden = true
			expandButton.isHidden = false
            error(text: "That operation would result in a total of \(newTotal) items, and Gladys will hold up to \(nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time in-app purchase.")
			return
		}

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

		let url = URL(string: "gladys://in-app-purchase/\(newTotal)")!

		cancelRequested(cancelButton) // warning: resets model counts from above!

		let selector = sel_registerName("openURL:")
		var responder = self as UIResponder?
		while let r = responder, !r.responds(to: selector) {
			responder = r.next
		}
		_ = responder?.perform(selector, with: url)
	}
    
    private func showBusy(_ busy: Bool) {
        check.isHidden = busy
        if busy {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

	@IBAction private func cancelRequested(_ sender: UIBarButtonItem) {

        newItems.forEach { $0.cancelIngest() }

        reset(ingestOnNextAppearance: true)

		let error = NSError(domain: GladysErrorDomain, code: 84, userInfo: [ NSLocalizedDescriptionKey: statusLabel.text ?? "No further info" ])
		extensionContext?.cancelRequest(withError: error)
	}

    @objc private func itemIngested(_ notification: Notification) {
        guard Model.doneIngesting else {
            return
		}

        showBusy(false)

        if PersistedOptions.setLabelsWhenActioning {
            labelsButton.isHidden = false
            navigationItem.rightBarButtonItem = makeDoneButton(target: self, action: #selector(signalDone))
        } else {
            signalDone()
        }
    }

    private func reset(ingestOnNextAppearance: Bool) {
        statusLabel.isHidden = true
        expandButton.isHidden = true
        labelsButton.isHidden = true
        labelsButton.isHidden = !PersistedOptions.setLabelsWhenActioning
        showBusy(false)
        
        ingestOnWillAppear = ingestOnNextAppearance
		newItems.removeAll()
        ActionRequestViewController.labelsToApply.removeAll()
		ActionRequestViewController.noteToApply = ""
		Model.reset()
	}
    
    @objc private func signalDone() {
        NotificationCenter.default.post(name: .DoneSelected, object: nil)
    }

	@objc private func done() {
        
        for item in newItems {
            item.labels = ActionRequestViewController.labelsToApply
            item.note = ActionRequestViewController.noteToApply
        }

        Model.insertNewItemsWithoutLoading(items: newItems, addToDrops: true)

        CloudManager.signalExtensionUpdate()
        
        dismiss(animated: true) {
            self.reset(ingestOnNextAppearance: true)
            self.extensionContext?.completeRequest(returningItems: nil) { _ in
                log("Dismissed")
            }
        }
	}
    
	////////////////////// Labels

    static var labelsToApply = [String]()
    static var noteToApply = ""
}
