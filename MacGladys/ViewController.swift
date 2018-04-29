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

final class ViewController: NSViewController, NSCollectionViewDelegate, NSCollectionViewDataSource, LoadCompletionDelegate {
	@IBOutlet weak var collection: NSCollectionView!

	private let dropCellId = NSUserInterfaceItemIdentifier.init("DropCell")
	private var loadingUUIDS = Set<UUID>()

	override func viewWillAppear() {
		if let w = view.window {
			updateCellSize(from: w.frame.size)
		}
		super.viewWillAppear()
	}

	private var observers = [NSObjectProtocol]()

	override func viewDidLoad() {
		super.viewDidLoad()

		let i = #imageLiteral(resourceName: "paper")
		i.resizingMode = .tile
		let v = NSImageView(image: i)
		v.imageScaling = .scaleAxesIndependently
		collection.backgroundView = v

		Model.reloadDataIfNeeded()

		if CloudManager.syncSwitchedOn {
			sync()
		}

		let a1 = NotificationCenter.default.addObserver(forName: Notification.Name.ExternalDataUpdated, object: nil, queue: .main) { [weak self] n in
			self?.postSave()
		}
		observers.append(a1)
		let a2 = NotificationCenter.default.addObserver(forName: Notification.Name.SaveComplete, object: nil, queue: .main) { [weak self] n in
			self?.postSave()
		}
		observers.append(a2)
		print("Loaded with \(Model.drops.count) items")
	}

	private func postSave() {
		collection.reloadData()
		for i in Model.drops where i.needsReIngest {
			loadingUUIDS.insert(i.uuid)
			i.reIngest(delegate: self)
		}
	}

	private func sync() {
		CloudManager.sync { error in
			DispatchQueue.main.async {
				if let error = error {
					print("Sync Error: \(error.finalDescription)")
				}
			}
		}
	}

	func loadCompleted(sender: AnyObject) {
		guard let o = sender as? ArchivedDropItem else { return }
		o.needsReIngest = false
		loadingUUIDS.remove(o.uuid)
		if let i = Model.filteredDrops.index(of: o) {
			let ip = IndexPath(item: i, section: 0)
			collection.reloadItems(at: [ip])
		}
		if loadingUUIDS.count == 0 {
			print("Ingest complete")
			Model.save()
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

	func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
		for i in indexPaths {
			let o = Model.filteredDrops[i.item]
			o.needsReIngest = true
			loadingUUIDS.insert(o.uuid)
			o.reIngest(delegate: self)
		}
	}

	override func viewWillTransition(to newSize: NSSize) {
		updateCellSize(from: newSize)
	}

	private func updateCellSize(from frameSize: NSSize) {
		let w = frameSize.width - 20
		let columns = (w / 200).rounded(.down)
		let leftOver = w.truncatingRemainder(dividingBy: 200)
		let s = 190 + (leftOver / columns)
		(collection.collectionViewLayout as! NSCollectionViewFlowLayout).itemSize = NSSize(width: s, height: s)
	}

	deinit {
		print("deinit")
		for o in observers {
			NotificationCenter.default.removeObserver(o)
		}
	}
}
