//
//  ViewController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

func genericAlert(title: String, message: String) {
	let a = NSAlert()
	a.messageText = title
	a.informativeText = message
	a.runModal()
}

final class WindowController: NSWindowController, NSWindowDelegate {
	func windowWillClose(_ notification: Notification) {
		NSApplication.shared.terminate(self)
	}
}

final class DropCell: NSCollectionViewItem {

	@IBOutlet weak var topLabel: NSTextField!
	@IBOutlet weak var bottomLabel: NSTextField!
	@IBOutlet weak var image: NSImageView!

	override var representedObject: Any? {
		didSet {
			guard let r = representedObject as? ArchivedDropItem else { return }
			topLabel.stringValue = r.displayText.0 ?? ""
			bottomLabel.stringValue = r.note
			image.image = r.displayIcon
		}
	}
}

final class ViewController: NSViewController, NSCollectionViewDelegate, NSCollectionViewDataSource {
	@IBOutlet weak var syncSwitch: NSButton!
	@IBOutlet weak var collection: NSCollectionView!

	private let dropCellId = NSUserInterfaceItemIdentifier.init("DropCell")

	override func viewDidLoad() {
		super.viewDidLoad()

		Model.reloadDataIfNeeded()

		if CloudManager.syncSwitchedOn {
			NSApplication.shared.registerForRemoteNotifications(matching: [.badge])
			syncSwitch.integerValue = 1
			CloudManager.sync { error in
				if let error = error {
					print("Sync Error: \(error.finalDescription)")
				}
			}
		} else {
			syncSwitch.integerValue = 0
		}

		print("Loaded with \(Model.drops.count) items")
	}

	@IBAction func syncSwitchChanged(_ sender: NSButton) {
		if CloudManager.syncSwitchedOn {
			CloudManager.deactivate(force: false) { error in
				DispatchQueue.main.async {
					if let error = error {
						genericAlert(title: "Could not change state", message: error.finalDescription)
					}
				}
			}
		} else {
			CloudManager.activate { error in
				DispatchQueue.main.async {
					if let error = error {
						genericAlert(title: "Could not change state", message: error.finalDescription)
					}
				}
			}
		}
	}

	func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
		return Model.filteredDrops.count
	}

	func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
		let i = collectionView.makeItem(withIdentifier: dropCellId, for: indexPath)
		i.representedObject = Model.filteredDrops[indexPath.item]
		return i
	}
}
