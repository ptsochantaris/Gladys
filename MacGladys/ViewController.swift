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

	override func viewDidLoad() {
		super.viewDidLoad()
		view.layer?.cornerRadius = 10
		view.layer?.backgroundColor = .white
	}
}

final class ViewController: NSViewController, NSCollectionViewDelegate, NSCollectionViewDataSource, LoadCompletionDelegate, NSWindowDelegate {
	@IBOutlet weak var syncSwitch: NSButton!
	@IBOutlet weak var collection: NSCollectionView!

	private let dropCellId = NSUserInterfaceItemIdentifier.init("DropCell")
	private var loadingUUIDS = Set<UUID>()

	override func viewWillAppear() {
		if let w = view.window {
			w.delegate = self
			updateCellSize(from: w.frame.size)
		}
		super.viewWillAppear()
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		Model.reloadDataIfNeeded()

		if CloudManager.syncSwitchedOn {
			NSApplication.shared.registerForRemoteNotifications(matching: [.badge])
			syncSwitch.integerValue = 1
			CloudManager.sync { error in
				DispatchQueue.main.async { [weak self] in
					guard let s = self else { return }
					if let error = error {
						print("Sync Error: \(error.finalDescription)")
					} else {
						for i in Model.drops where i.needsReIngest {
							s.loadingUUIDS.insert(i.uuid)
							i.reIngest(delegate: s)
						}
					}
				}
			}
		} else {
			syncSwitch.integerValue = 0
		}

		print("Loaded with \(Model.drops.count) items")
	}

	func loadCompleted(sender: AnyObject) {
		guard let o = sender as? ArchivedDropItem else { return }
		loadingUUIDS.remove(o.uuid)
		if loadingUUIDS.count == 0 {
			print("Ingest complete")
			collection.reloadData()
			Model.save()
		}
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

	func windowWillClose(_ notification: Notification) {
		NSApplication.shared.terminate(self)
	}

	func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
		updateCellSize(from: frameSize)
		return frameSize
	}

	private func updateCellSize(from frameSize: NSSize) {
		let w = frameSize.width - 20
		let columns = (w / 200).rounded(.down)
		let leftOver = w.truncatingRemainder(dividingBy: 200)
		let s = 190 + (leftOver / columns)
		(collection.collectionViewLayout as! NSCollectionViewFlowLayout).itemSize = NSSize(width: s, height: s)
	}
}
