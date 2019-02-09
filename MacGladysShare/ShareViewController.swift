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
				log("Ingesting inputItem with text: [\(text.string)]")
				pasteboardItems.append(text)

			} else if let title = inputItem.attributedTitle {
				log("Ingesting inputItem with title: [\(title.string)]")
				pasteboardItems.append(title)

			} else {
				log("Ingesting inputItem with \(inputItem.attachments?.count ?? 0) attachment(s)...")
				for attachment in inputItem.attachments ?? [] {
					let newItem = NSPasteboardItem()
					pasteboardItems.append(newItem)
					var identifiers = attachment.registeredTypeIdentifiers
					if identifiers.contains("public.file-url") && identifiers.contains("public.url") { // finder is sharing
						log("> Removing Finder redundant URL data")
						identifiers.removeAll { $0 == "public.file-url" || $0 == "public.url" }
					}
					log("> Ingesting data with identifiers: \(identifiers.joined(separator: ", "))")
					for type in identifiers {
						importGroup.enter()
						let p = attachment.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, error in
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
				log("Ingest cancelled")
				let error = NSError(domain: GladysErrorDomain, code: 84, userInfo: [ NSLocalizedDescriptionKey: "User cancelled" ])
				extensionContext.cancelRequest(withError: error)
				return
			}

			log("Writing data to parent app...")
			s.cancelButton.isHidden = true
			s.pasteboard.clearContents()
			s.pasteboard.writeObjects(pasteboardItems)
			DistributedNotificationCenter.default().addObserver(s, selector: #selector(s.pasteDone), name: .SharingPasteboardPasted, object: "build.bru.MacGladys")
			DispatchQueue.main.async {
				if !NSWorkspace.shared.open(URL(string: "gladys://x-callback-url/paste-share-pasteboard")!) {
					log("Main app could not be opened")
					let error = NSError(domain: GladysErrorDomain, code: 88, userInfo: [ NSLocalizedDescriptionKey: "Main app could not be opened" ])
					extensionContext.cancelRequest(withError: error)
				}
			}
		}
	}

	deinit {
		DistributedNotificationCenter.default().removeObserver(self)
	}

	@objc private func pasteDone() {
		log("Main app ingest done.")
		pasteboard.clearContents()
		extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
	}

}
