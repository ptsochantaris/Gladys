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

	static var shared: ViewController! = nil

	private let dropCellId = NSUserInterfaceItemIdentifier("DropCell")
	private var loadingUUIDS = Set<UUID>()

	static let labelColor = NSColor.labelColor
	static let tintColor = #colorLiteral(red: 0.5764705882, green: 0.09411764706, blue: 0.07058823529, alpha: 1)

	@IBOutlet weak var searchHolder: NSView!
	@IBOutlet weak var searchBar: NSSearchField!

	override func viewWillAppear() {
		if let w = view.window {
			updateCellSize(from: w.frame.size)
		}
		updateTitle()
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

		let n = NotificationCenter.default

		let a1 = n.addObserver(forName: .ExternalDataUpdated, object: nil, queue: .main) { [weak self] _ in
			self?.detectExternalDeletions()
			Model.rebuildLabels()
			Model.forceUpdateFilter(signalUpdate: true) // refresh filtered items
			self?.postSave()
		}
		observers.append(a1)

		let a2 = n.addObserver(forName: .SaveComplete, object: nil, queue: .main) { [weak self] _ in
			self?.collection.reloadData()
			self?.postSave()
		}
		observers.append(a2)

		let a3 = n.addObserver(forName: .ItemCollectionNeedsDisplay, object: nil, queue: .main) { [weak self] _ in
			self?.collection.reloadData()
		}
		observers.append(a3)

		let a4 = n.addObserver(forName: .CloudManagerStatusChanged, object: nil, queue: .main) { [weak self] _ in
			self?.updateTitle()
		}
		observers.append(a4)

		let a5 = n.addObserver(forName: .LabelSelectionChanged, object: nil, queue: .main) { _ in
			Model.forceUpdateFilter(signalUpdate: true)
		}
		observers.append(a5)

		print("Loaded with \(Model.drops.count) items")
		updateTitle()
	}

	private func updateTitle() {
		if let syncStatus = CloudManager.syncProgressString {
			view.window?.title = "Gladys: \(syncStatus)"
		} else {
			view.window?.title = "Gladys"
		}
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
		o.reIndex()
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

	override func viewWillLayout() {
		super.viewWillLayout()
		if let f = view.window?.frame.size {
			updateCellSize(from: f)
		}
	}

	private func updateCellSize(from frameSize: NSSize) {
		let baseSize: CGFloat = 180
		let w = frameSize.width - 10
		let columns = (w / baseSize).rounded(.down)
		let leftOver = w.truncatingRemainder(dividingBy: baseSize)
		let s = ((baseSize - 10) + (leftOver / columns)).rounded(.down)
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
		if let item = Model.item(uuid: identifier) {
			if let i = Model.drops.index(of: item) {
				let ip = IndexPath(item: i, section: 0)
				collection.scrollToItems(at: [ip], scrollPosition: .centeredVertically)
				collection.selectionIndexes = IndexSet(integer: i)
				info(nil)
			}
		}
	}

	func startSearch(initialText: String) {
		searchHolder.isHidden = false
		searchBar.stringValue = initialText
		updateSearch()
	}

	func collectionView(_ collectionView: NSCollectionView, writeItemsAt indexPaths: Set<IndexPath>, to pasteboard: NSPasteboard) -> Bool {
		let pasteboardItems = indexPaths.map { Model.filteredDrops[$0.item].pasteboardItem }
		pasteboard.writeObjects(pasteboardItems)
		return true
	}

	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
		return !indexPaths.map { Model.filteredDrops[$0.item].isLocked }.contains(true)
	}

	func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
		proposedDropOperation.pointee = .before
		return draggingIndexPaths == nil ? .copy : .move
	}

	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
		draggingIndexPaths = Array(indexPaths)
	}

	private var draggingIndexPaths: [IndexPath]?

	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
		if let d = draggingIndexPaths, !d.isEmpty {
			if PersistedOptions.removeItemsWhenDraggedOut {
				let items = d.map { Model.filteredDrops[$0.item] }
				deleteRequested(for: items)
			}
			draggingIndexPaths = nil
		}
	}

	func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
		if let s = draggingInfo.draggingSource() as? NSCollectionView, s == collectionView, let draggingIndexPaths = draggingIndexPaths {

			var destinationIndex = Model.nearestUnfilteredIndexForFilteredIndex(indexPath.item)
			for draggingIndexPath in draggingIndexPaths.sorted(by: { $0.item > $1.item }) {
				let sourceItem = Model.filteredDrops[draggingIndexPath.item]
				let sourceIndex = Model.drops.index(of: sourceItem)!
				if destinationIndex > sourceIndex {
					destinationIndex -= 1
				}
				Model.drops.remove(at: sourceIndex)
				Model.drops.insert(sourceItem, at: destinationIndex)
			}
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

	@objc func info(_ sender: Any?) {
		let g = NSPasteboard.general
		g.clearContents()
		var paths = collection.selectionIndexPaths
		if let cell = sender as? DropCell, let item = cell.representedObject as? ArchivedDropItem, let index = Model.filteredDrops.index(of: item) {
			let ip = IndexPath(item: index, section: 0)
			paths.insert(ip)
		}
		for index in paths {
			let item = Model.filteredDrops[index.item]
			performSegue(withIdentifier: NSStoryboardSegue.Identifier("showDetail"), sender: item)
		}
	}

	@objc func open(_ sender: Any?) {
		let g = NSPasteboard.general
		g.clearContents()
		var paths = collection.selectionIndexPaths
		if let cell = sender as? DropCell, let item = cell.representedObject as? ArchivedDropItem, let index = Model.filteredDrops.index(of: item) {
			let ip = IndexPath(item: index, section: 0)
			paths.insert(ip)
		}
		for index in paths {
			let item = Model.filteredDrops[index.item]
			item.tryOpen(from: self)
		}
	}

	@objc func copy(_ sender: Any?) {
		let g = NSPasteboard.general
		g.clearContents()
		var paths = collection.selectionIndexPaths
		if let cell = sender as? DropCell, let item = cell.representedObject as? ArchivedDropItem, let index = Model.filteredDrops.index(of: item) {
			let ip = IndexPath(item: index, section: 0)
			paths.insert(ip)
		}
		for index in paths {
			let item = Model.filteredDrops[index.item]
			g.writeObjects([item.pasteboardItem])
		}
	}

	@objc func delete(_ sender: Any?) {
		var paths = collection.selectionIndexPaths
		if let cell = sender as? DropCell, let item = cell.representedObject as? ArchivedDropItem, let index = Model.filteredDrops.index(of: item) {
			let ip = IndexPath(item: index, section: 0)
			paths.insert(ip)
		}
		let items = paths.map { Model.filteredDrops[$0.item] }
		if !items.isEmpty {
			ViewController.shared.deleteRequested(for: items)
		}
	}

	@objc func paste(_ sender: Any?) {
		addItem(from: NSPasteboard.general, at: IndexPath(item: 0, section: 0))
	}

	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(copy(_:)), #selector(delete(_:)):
			return collection.selectionIndexes.count > 0
		case #selector(paste(_:)):
			return NSPasteboard.general.pasteboardItems?.count ?? 0 > 0
		default:
			return true
		}
	}

	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: nil)
		if segue.identifier?.rawValue == "showDetail",
			let item = sender as? ArchivedDropItem,
			let window = segue.destinationController as? NSWindowController,
			let d = window.contentViewController as? DetailController {

			d.representedObject = item
		}
	}
}
