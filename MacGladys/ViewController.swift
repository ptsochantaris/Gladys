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
	func windowDidResize(_ notification: Notification) {
		ViewController.shared.sizeChanged(to: window!.frame.size)
	}
}

final class ViewController: NSViewController, NSCollectionViewDelegate, NSCollectionViewDataSource, LoadCompletionDelegate {
	@IBOutlet weak var collection: NSCollectionView!

	static var shared: ViewController! = nil

	private let dropCellId = NSUserInterfaceItemIdentifier.init("DropCell")
	private var loadingUUIDS = Set<UUID>()

	static let labelColor = NSColor.labelColor
	static let tintColor = #colorLiteral(red: 0.5764705882, green: 0.09411764706, blue: 0.07058823529, alpha: 1)

	@IBOutlet weak var searchHolder: NSView!
	@IBOutlet weak var searchBar: NSSearchField!

	override func viewWillAppear() {
		if let w = view.window {
			updateCellSize(from: w.frame.size)
		}
		super.viewWillAppear()
	}

	func reloadData() {
		collection.reloadData()
	}

	private var observers = [NSObjectProtocol]()

	override func viewDidLoad() {
		super.viewDidLoad()

		ViewController.shared = self
		searchHolder.isHidden = true

		collection.registerForDraggedTypes([NSPasteboard.PasteboardType(kUTTypeItem as String)])
		collection.setDraggingSourceOperationMask(.move, forLocal: true)

		let i = #imageLiteral(resourceName: "paper")
		i.resizingMode = .tile
		let v = NSImageView(image: i)
		v.imageScaling = .scaleAxesIndependently
		collection.backgroundView = v

		Model.reloadDataIfNeeded()

		if CloudManager.syncSwitchedOn {
			sync()
		}

		let a1 = NotificationCenter.default.addObserver(forName: .ExternalDataUpdated, object: nil, queue: .main) { [weak self] n in
			Model.forceUpdateFilter(signalUpdate: false) // refresh filtered items
			self?.postSave()
		}
		observers.append(a1)

		let a2 = NotificationCenter.default.addObserver(forName: .SaveComplete, object: nil, queue: .main) { [weak self] n in
			self?.postSave()
		}
		observers.append(a2)

		let a3 = NotificationCenter.default.addObserver(forName: .ItemCollectionNeedsDisplay, object: nil, queue: .main) { [weak self] n in
			self?.collection.reloadData()
		}
		observers.append(a3)

		print("Loaded with \(Model.drops.count) items")
	}

	private func postSave() {
		collection.reloadData()
		for i in Model.drops where i.needsReIngest {
			loadingUUIDS.insert(i.uuid)
			i.reIngest(delegate: self)
			i.reIndex()
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
		/*for i in indexPaths {
			let item = collectionView.item(at: i)

		}*/
	}

	func sizeChanged(to newSize: NSSize) {
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
		for o in observers {
			NotificationCenter.default.removeObserver(o)
		}
	}

	@IBAction func searchDoneSelected(_ sender: NSButton) {
		resetSearch()
	}

	private func resetSearch() {
		searchBar.stringValue = ""
		searchHolder.isHidden = true
		updateSearch()
	}

	@IBAction func findSelected(_ sender: NSMenuItem) {
		searchHolder.isHidden = !searchHolder.isHidden
		if !searchHolder.isHidden {
			view.window?.makeFirstResponder(searchBar)
		}
	}

	override func controlTextDidChange(_ obj: Notification) {
		updateSearch()
	}

	private func updateSearch() {
		let s = searchBar.stringValue
		Model.filter = s.isEmpty ? nil : s
	}

	func highlightItem(with identifier: String, andOpen: Bool) {
		resetSearch()
		if let item = Model.item(uuid: identifier), let title = item.displayText.0 {
			print("should highlight \(title) too, and handle `andOpen`")
			if let i = Model.drops.index(of: item) {
				let ip = IndexPath(item: i, section: 0)
				collection.scrollToItems(at: [ip], scrollPosition: .centeredVertically)
			}
		}
	}

	func startSearch(initialText: String) {
		searchHolder.isHidden = false
		searchBar.stringValue = initialText
		updateSearch()
	}

	func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
		return Model.filteredDrops[indexPath.item].pasteboardWriter
	}

	func collectionView(_ collectionView: NSCollectionView, writeItemsAt indexPaths: Set<IndexPath>, to pasteboard: NSPasteboard) -> Bool {
		let writers = indexPaths.map { Model.filteredDrops[$0.item].pasteboardWriter }
		pasteboard.writeObjects(writers)
		return true
	}

	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
		return !indexPaths.map { Model.filteredDrops[$0.item].isLocked }.contains(true)
	}

	func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
		if let s = draggingInfo.draggingSource() as? NSCollectionView, s == collectionView {
			return .move
		} else {
			return .copy
		}
	}

	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
		draggingIndexPath = indexPaths.first
	}

	private var draggingIndexPath: IndexPath?

	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
		draggingIndexPath = nil
	}

	func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
		if let s = draggingInfo.draggingSource() as? NSCollectionView, s == collectionView, let draggingIndexPath = draggingIndexPath {

			let sourceItem = Model.filteredDrops[draggingIndexPath.item]
			let sourceIndex = Model.drops.index(of: sourceItem)!
			var destinationIndex = Model.nearestUnfilteredIndexForFilteredIndex(indexPath.item)
			if destinationIndex > sourceIndex {
				destinationIndex -= 1
			}
			Model.drops.remove(at: sourceIndex)
			Model.drops.insert(sourceItem, at: destinationIndex)
			Model.forceUpdateFilter(signalUpdate: false)
			collectionView.reloadData()
			Model.save()
			return true
		} else {


			return false
		}
	}
}
