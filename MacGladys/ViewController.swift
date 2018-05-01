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
	func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
		ViewController.shared.sizeChanged(to: frameSize)
		return frameSize
	}
}

final class GladysCollection: NSCollectionView {

	override func keyDown(with event: NSEvent) {
		if event.keyCode == 36 {
			ViewController.shared.selected()
		} else {
			super.keyDown(with: event)
		}
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
		collection.setDraggingSourceOperationMask(.copy, forLocal: false)

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
			self?.detectExternalDeletions()
			Model.forceUpdateFilter(signalUpdate: true) // refresh filtered items
			self?.postSave()
		}
		observers.append(a1)

		let a2 = NotificationCenter.default.addObserver(forName: .SaveComplete, object: nil, queue: .main) { [weak self] n in
			self?.collection.reloadData()
			self?.postSave()
		}
		observers.append(a2)

		let a3 = NotificationCenter.default.addObserver(forName: .ItemCollectionNeedsDisplay, object: nil, queue: .main) { [weak self] n in
			self?.collection.reloadData()
		}
		observers.append(a3)

		print("Loaded with \(Model.drops.count) items")
	}

	private func detectExternalDeletions() {
		var shouldSaveInAnyCase = false
		for item in Model.drops.filter({ !$0.needsDeletion }) { // partial deletes
			let componentsToDelete = item.typeItems.filter { $0.needsDeletion }
			if componentsToDelete.count > 0 {
				item.typeItems = item.typeItems.filter { !$0.needsDeletion }
				for c in componentsToDelete {
					c.deleteFromStorage()
				}
				item.needsReIngest = true
				shouldSaveInAnyCase = !CloudManager.syncing // this could be from the file provider
			}
		}
		let itemsToDelete = Model.drops.filter { $0.needsDeletion }
		if itemsToDelete.count > 0 {
			deleteRequested(for: itemsToDelete) // will also save
		} else if shouldSaveInAnyCase {
			Model.save()
		}
	}

	private func postSave() {
		let itemsToReIngest = Model.drops.filter { $0.needsReIngest && $0.loadingProgress == nil && !$0.isDeleting && !loadingUUIDS.contains($0.uuid) }
		for i in itemsToReIngest {
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
	}

	func selected() {
		guard let i = collection.selectionIndexPaths.first else { return }
		let item = Model.filteredDrops[i.item]
		print(item.uuid)
	}

	func sizeChanged(to newSize: NSSize) {
		updateCellSize(from: newSize)
	}

	private func updateCellSize(from frameSize: NSSize) {
		let baseSize: CGFloat = 180
		let w = frameSize.width - 10
		let columns = (w / baseSize).rounded(.down)
		let leftOver = w.truncatingRemainder(dividingBy: baseSize)
		let s = (baseSize - 10) + (leftOver / columns)
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
		return draggingIndexPath == nil ? .copy : .move
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
			Model.forceUpdateFilter(signalUpdate: true)
			Model.save()
			return true
		} else {
			let p = draggingInfo.draggingPasteboard()
			return addItem(from: p, at: indexPath)
		}
	}

	@discardableResult
	private func addItem(from pasteBoard: NSPasteboard, at indexPath: IndexPath) -> Bool {
		guard let types = pasteBoard.types else { return false }

		var count = 0
		let i = NSItemProvider()
		for type in types.filter({ $0.rawValue.contains(".") && !$0.rawValue.contains(" ") && !$0.rawValue.contains("dyn.") }) {
			if let data = pasteBoard.data(forType: type) {
				if !data.isEmpty {
					count += 1
					i.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { callback -> Progress? in
						let p = Progress()
						p.totalUnitCount = 1
						DispatchQueue.global(qos: .userInitiated).async {
							callback(data, nil)
							p.completedUnitCount = 1
						}
						return p
					}
				}
			}
		}
		if count == 0 { return false }
		let newItems = ArchivedDropItem.importData(providers: [i], delegate: self, overrides: nil, pasteboardName: pasteBoard.name.rawValue)
		for newItem in newItems {
			loadingUUIDS.insert(newItem.uuid)
			let destinationIndex = Model.nearestUnfilteredIndexForFilteredIndex(indexPath.item)
			Model.drops.insert(newItem, at: destinationIndex)
		}
		Model.forceUpdateFilter(signalUpdate: true)
		return true
	}

	func deleteRequested(for items: [ArchivedDropItem]) {

		for item in items {

			if item.shouldDisplayLoading {
				item.cancelIngest()
			}

			let uuid = item.uuid
			loadingUUIDS.remove(uuid)

			if let i = Model.filteredDrops.index(where: { $0.uuid == uuid }) {
				Model.removeItemFromList(uuid: uuid)
				collection.deleteItems(at: [IndexPath(item: i, section: 0)])
			}

			item.delete()
		}

		Model.save()
	}

	@objc func copy(_ sender: Any?) {
		guard let i = collection.selectionIndexPaths.first else { return }
		let item = Model.filteredDrops[i.item]
		let g = NSPasteboard.general
		g.clearContents()
		g.writeObjects([item.pasteboardWriter])
	}

	@objc func paste(_ sender: Any?) {
		addItem(from: NSPasteboard.general, at: IndexPath(item: 0, section: 0))
	}
}
