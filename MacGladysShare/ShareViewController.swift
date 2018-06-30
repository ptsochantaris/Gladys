//
//  ShareViewController.swift
//  MacGladysShare
//
//  Created by Paul Tsochantaris on 30/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

class ShareViewController: NSViewController {

    override var nibName: NSNib.Name? {
        return NSNib.Name("ShareViewController")
    }

	@IBOutlet private weak var spinner: NSProgressIndicator!
	@IBOutlet private weak var cancelButton: NSButton!

	private var cancelled = false
	private var progresses = [Progress]()
	private let importGroup = DispatchGroup()
	private let pasteboard = NSPasteboard(name: sharingPasteboard)

	@IBAction private func cancelButtonSelected(_ sender: NSButton) {
		cancelled = true
		for p in progresses where !p.isFinished {
			p.cancel()
			importGroup.leave()
		}
		progresses.removeAll()
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		spinner.startAnimation(nil)

		guard let extensionContext = extensionContext else { return }

		var pasteboardItems = [NSPasteboardWriting]()

		for inputItem in extensionContext.inputItems as? [NSExtensionItem] ?? [] {
			if let text = inputItem.attributedContentText {
				pasteboardItems.append(text)
			} else if let title = inputItem.attributedTitle {
				pasteboardItems.append(title)
			} else if let providers = inputItem.attachments as? [NSItemProvider] {
				for provider in providers {
					let newItem = NSPasteboardItem()
					pasteboardItems.append(newItem)
					for type in provider.registeredTypeIdentifiers {
						importGroup.enter()
						let p = provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, error in
							guard let s = self else { return }
							if let data = data {
								newItem.setData(data, forType: NSPasteboard.PasteboardType(type))
							}
							s.importGroup.leave()
						}
						progresses.append(p)
					}
				}
			}
		}

		importGroup.notify(queue: DispatchQueue.main) { [weak self] in
			guard let s = self else { return }

			if s.cancelled {
				let error = NSError(domain: "build.bru.Gladys.error", code: 84, userInfo: [ NSLocalizedDescriptionKey: "User cancelled" ])
				extensionContext.cancelRequest(withError: error)
				return
			}

			s.cancelButton.isHidden = true
			s.pasteboard.clearContents()
			s.pasteboard.writeObjects(pasteboardItems)
			DistributedNotificationCenter.default().addObserver(s, selector: #selector(s.pasteDone), name: .SharingPasteboardPasted, object: "build.bru.MacGladys")
			if !NSWorkspace.shared.open(URL(string: "gladys://x-callback-url/paste-share-pasteboard")!) {
				let error = NSError(domain: "build.bru.Gladys.error", code: 88, userInfo: [ NSLocalizedDescriptionKey: "Main app could not be opened" ])
				extensionContext.cancelRequest(withError: error)
			}
		}
	}

	deinit {
		DistributedNotificationCenter.default().removeObserver(self)
	}

	@objc private func pasteDone() {
		pasteboard.clearContents()
		extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
	}

}
