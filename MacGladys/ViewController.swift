//
//  ViewController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa
import Quartz
import MacGladysFramework

func genericAlert(title: String, message: String?, on viewController: NSViewController) {
	let a = NSAlert()
	a.messageText = title
	if let message = message {
		a.informativeText = message
	}
	a.beginSheetModal(for: viewController.view.window!, completionHandler: nil)
}

final class WindowController: NSWindowController, NSWindowDelegate {
	func windowWillClose(_ notification: Notification) {
		ViewController.shared.lockUnlockedItems()
	}

	func windowDidBecomeKey(_ notification: Notification) {
		ViewController.shared.isKey()
	}

	func windowDidMove(_ notification: Notification) {
		if let w = window, w.isVisible {
			lastWindowPosition = w.frame
		}
	}

	func windowDidResize(_ notification: Notification) {
		if let w = window, w.isVisible {
			lastWindowPosition = w.frame
		}
	}

	func windowDidEndLiveResize(_ notification: Notification) {
		ViewController.shared.collection.reloadData()
	}

	var lastWindowPosition: NSRect? {
		set {
			PersistedOptions.defaults.setValue(newValue?.dictionaryRepresentation, forKey: "lastWindowPosition")
		}
		get {
			if let d = PersistedOptions.defaults.value(forKey: "lastWindowPosition") as? NSDictionary {
				return NSRect(dictionaryRepresentation: d)
			} else {
				return nil
			}
		}
	}

	override func windowDidLoad() {
		super.windowDidLoad()
		if let f = lastWindowPosition {
			window?.setFrame(f, display: false)
		}
		let v = window?.contentView
		let i = #imageLiteral(resourceName: "paper")
		i.resizingMode = .tile
		v?.layer?.contents = i
		v?.layer?.contentsGravity = kCAGravityResize
	}

	private var firstShow = true
	override func showWindow(_ sender: Any?) {
		if firstShow && PersistedOptions.hideMainWindowAtStartup {
			return
		}
		firstShow = false
		super.showWindow(sender)
	}
}

final class MainCollectionView: NSCollectionView {
	override func keyDown(with event: NSEvent) {
		if event.charactersIgnoringModifiers == " " {
			ViewController.shared.toggleQuickLookPreviewPanel(self)
		} else {
			super.keyDown(with: event)
		}
	}
}

final class ViewController: NSViewController, NSCollectionViewDelegate, NSCollectionViewDataSource, LoadCompletionDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
	@IBOutlet weak var collection: NSCollectionView!

	static var shared: ViewController! = nil

	private let dropCellId = NSUserInterfaceItemIdentifier("DropCell")

	static let labelColor = NSColor.labelColor
	static let tintColor = #colorLiteral(red: 0.5764705882, green: 0.09411764706, blue: 0.07058823529, alpha: 1)

	@IBOutlet weak var searchHolder: NSView!
	@IBOutlet weak var searchBar: NSSearchField!

	@IBOutlet weak var emptyView: NSImageView!
	@IBOutlet weak var emptyLabel: NSTextField!

	override func viewWillAppear() {
		if let w = view.window {
			updateCellSize(from: w.frame.size)
		}
		updateTitle()
		super.viewWillAppear()
	}

	func reloadData(inserting: [IndexPath]? = nil, deleting: [IndexPath]? = nil) {
		if let inserting = inserting {
			collection.deselectAll(nil)
			collection.animator().insertItems(at: Set(inserting))
		} else if let deleting = deleting {
			collection.deselectAll(nil)
			collection.animator().deleteItems(at: Set(deleting))
		} else {
			collection.animator().reloadData()
		}
	}

	private func updateDragOperationIndicators() {
		collection.setDraggingSourceOperationMask(.move, forLocal: true)
		collection.setDraggingSourceOperationMask(optionPressed ? .every : .copy, forLocal: false)
	}

	private var observers = [NSObjectProtocol]()

	override func viewDidLoad() {
		super.viewDidLoad()

		ViewController.shared = self
		searchHolder.isHidden = true

		collection.registerForDraggedTypes([NSPasteboard.PasteboardType(kUTTypeItem as String), NSPasteboard.PasteboardType(kUTTypeContent as String)])
		updateDragOperationIndicators()

		Model.reloadDataIfNeeded()

		let n = NotificationCenter.default

		let a1 = n.addObserver(forName: .ExternalDataUpdated, object: nil, queue: .main) { [weak self] _ in
			self?.detectExternalDeletions()
			Model.rebuildLabels()
			Model.forceUpdateFilter(signalUpdate: false) // refresh filtered items
			self?.reloadData()
			self?.postSave()
		}
		observers.append(a1)

		let a2 = n.addObserver(forName: .SaveComplete, object: nil, queue: .main) { [weak self] _ in
			self?.updateTitle()
			self?.reloadData()
			self?.postSave()
		}
		observers.append(a2)

		let a3 = n.addObserver(forName: .ItemCollectionNeedsDisplay, object: nil, queue: .main) { [weak self] _ in
			self?.updateTitle()
			self?.reloadData()
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

		if CloudManager.syncSwitchedOn {
			CloudManager.sync { error in
				DispatchQueue.main.async {
					if let error = error {
						log("Sync Error: \(error.finalDescription)")
					}
				}
			}
		}

		updateTitle()
		postSave()

		if Model.drops.count == 0 {
			blurb("Ready! Drop me stuff.")
		}
	}

	private var optionPressed: Bool {
		return NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
	}

	private func updateTitle() {
		var title: String
		if Model.isFilteringLabels {
			title = Model.enabledLabelsForTitles.joined(separator: ", ")
		} else {
			title = "Gladys"
		}
		if let syncStatus = CloudManager.syncProgressString {
			view.window?.title = "\(title) — \(syncStatus)"
		} else {
			view.window?.title = title
		}
	}

	func isKey() {
		if Model.filteredDrops.count == 0 {
			blurb(Greetings.randomGreetLine)
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
		let itemsToReIngest = Model.drops.filter { $0.needsReIngest && $0.loadingProgress == nil && !$0.isDeleting && !Model.loadingUUIDs.contains($0.uuid) }
		for i in itemsToReIngest {
			Model.loadingUUIDs.insert(i.uuid)
			i.reIngest(delegate: self)
		}
		updateEmptyView()
	}

	func loadCompleted(sender: AnyObject) {
		guard let o = sender as? ArchivedDropItem else { return }
		o.needsReIngest = false
		o.reIndex()
		Model.loadingUUIDs.remove(o.uuid)
		if let i = Model.filteredDrops.index(of: o) {
			let ip = IndexPath(item: i, section: 0)
			collection.reloadItems(at: [ip])
		}
		if Model.loadingUUIDs.count == 0 {
			log("Ingest complete")
			Model.save()
		}
	}

	func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
		if collection.selectionIndexPaths.count > 0 && QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
			QLPreviewPanel.shared().reloadData()
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

	@objc func shareSelected(_ sender: Any?) {
		guard let itemToShare = actionableSelectedItems.first,
			let shareableItem = itemToShare.mostRelevantOpenItem?.itemForShare.0,
			let i = Model.filteredDrops.index(of: itemToShare),
			let cell = collection.item(at: IndexPath(item: i, section: 0))
			else { return }

		collection.deselectAll(nil)
		collection.selectItems(at: [IndexPath(item: i, section: 0)], scrollPosition: [])
		let p = NSSharingServicePicker(items: [shareableItem])
		let f = cell.view.frame
		let centerFrame = NSRect(origin: CGPoint(x: f.midX-1, y: f.midY-1), size: CGSize(width: 2, height: 2))
		DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
			p.show(relativeTo: centerFrame, of: self.collection, preferredEdge: .minY)
		}
	}

	@IBAction func searchDoneSelected(_ sender: NSButton) {
		resetSearch(andLabels: false)
	}

	private func resetSearch(andLabels: Bool) {
		searchBar.stringValue = ""
		searchHolder.isHidden = true
		updateSearch()

		if andLabels {
			Model.disableAllLabels()
		}

		if Model.filter == nil { // because the next line won't have any effect if it's already nil
			Model.forceUpdateFilter(signalUpdate: true)
		} else {
			Model.filter = nil
		}
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
		resetSearch(andLabels: true)
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
		let pasteboardItems = indexPaths.compactMap { Model.filteredDrops[$0.item].pasteboardItem }
		pasteboard.writeObjects(pasteboardItems)
		let filePromises = indexPaths.compactMap { Model.filteredDrops[$0.item].filePromise }
		pasteboard.writeObjects(filePromises)
		return true
	}

	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
		return !indexPaths.map { Model.filteredDrops[$0.item].needsUnlock }.contains(true)
	}

	func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
		proposedDropOperation.pointee = .on
		return draggingIndexPaths == nil ? .copy : .move
	}

	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
		updateDragOperationIndicators()
		draggingIndexPaths = Array(indexPaths)
	}

	private var draggingIndexPaths: [IndexPath]?

	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
		if let d = draggingIndexPaths, !d.isEmpty {
			if optionPressed {
				let items = d.map { Model.filteredDrops[$0.item] }
				deleteRequested(for: items)
			}
			draggingIndexPaths = nil
		}
	}

	func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
		if let s = draggingInfo.draggingSource() as? NSCollectionView, s == collectionView, let dip = draggingIndexPaths {

			draggingIndexPaths = nil
			if let firstDip = dip.first, firstDip == indexPath {
				return false
			}
			
			let destinationIndex = Model.nearestUnfilteredIndexForFilteredIndex(indexPath.item)
			for draggingIndexPath in dip.sorted(by: { $0.item > $1.item }) {
				let sourceItem = Model.filteredDrops[draggingIndexPath.item]
				let sourceIndex = Model.drops.index(of: sourceItem)!
				Model.drops.remove(at: sourceIndex)
				Model.drops.insert(sourceItem, at: destinationIndex)
				collection.animator().moveItem(at: IndexPath(item: sourceIndex, section: 0), to: IndexPath(item: destinationIndex, section: 0))
				collection.deselectAll(nil)
			}
			Model.forceUpdateFilter(signalUpdate: false)
			Model.save()
			return true
		} else {
			let p = draggingInfo.draggingPasteboard()
			return addItems(from: p, at: indexPath, overrides: nil)
		}
	}

	@discardableResult
	func addItems(from pasteBoard: NSPasteboard, at indexPath: IndexPath, overrides: ImportOverrides?) -> Bool {
		guard let pasteboardItems = pasteBoard.pasteboardItems else { return false }

		let itemProviders = pasteboardItems.compactMap { pasteboardItem -> NSItemProvider? in
			let extractor = NSItemProvider()
			var count = 0
			for type in pasteboardItem.types {
				if let data = pasteboardItem.data(forType: type), !data.isEmpty {
					count += 1
					extractor.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { callback -> Progress? in
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
			return count > 0 ? extractor : nil
		}

		if itemProviders.isEmpty {
			return false
		}

		return _addItems(itemProviders: itemProviders, name: pasteBoard.name.rawValue, indexPath: indexPath, overrides: overrides)
	}

	@discardableResult
	private func _addItems(itemProviders: [NSItemProvider], name: String?, indexPath: IndexPath, overrides: ImportOverrides?) -> Bool {
		if IAPManager.shared.checkInfiniteMode(for: itemProviders.count) {
			return false
		}

		var insertedIndexPaths = [IndexPath]()
		var count = 0
		for provider in itemProviders {
			for newItem in ArchivedDropItem.importData(providers: [provider], delegate: self, overrides: overrides, pasteboardName: name) {
				Model.loadingUUIDs.insert(newItem.uuid)

				var modelIndex = indexPath.item
				if Model.isFiltering {
					modelIndex = Model.nearestUnfilteredIndexForFilteredIndex(indexPath.item)
					if Model.isFilteringLabels && !PersistedOptions.dontAutoLabelNewItems {
						newItem.labels = Model.enabledLabelsForItems
					}
				}
				Model.drops.insert(newItem, at: modelIndex)

				let finalIndex = IndexPath(item: indexPath.item + count, section: 0)
				insertedIndexPaths.append(finalIndex)
				count += 1
			}
		}

		if Model.forceUpdateFilter(signalUpdate: false) {
			reloadData(inserting: insertedIndexPaths)
		} else if Model.isFiltering && count > 0 {
			let a = NSAlert()
			a.messageText = count > 1 ? "Items Added" : "Item Added"
			a.beginSheetModal(for: view.window!, completionHandler: nil)
		}
		return true
	}

	func importFiles(paths: [String]) {
		let providers = paths.compactMap { path -> NSItemProvider? in
			let url = NSURL(fileURLWithPath: path)
			var isDir: ObjCBool = false
			FileManager.default.fileExists(atPath: url.path ?? "", isDirectory: &isDir)
			if isDir.boolValue {
				return NSItemProvider(item: url, typeIdentifier: kUTTypeFileURL as String)
			} else {
				return NSItemProvider(contentsOf: url as URL)
			}
		}
		_addItems(itemProviders: providers, name: nil, indexPath: IndexPath(item: 0, section: 0), overrides: nil)
	}

	func deleteRequested(for items: [ArchivedDropItem]) {

		let ipsToRemove = Model.delete(items: items)
		if !ipsToRemove.isEmpty {
			reloadData(deleting: ipsToRemove)
		}

		Model.save()

		if Model.filteredDrops.count == 0 {
			blurb(Greetings.randomCleanLine)
		}
	}

	@objc func removeLock(_ sender: Any?) {
		if let sender = sender as? DropCell, let cellItem = sender.representedObject as? ArchivedDropItem, let index = Model.filteredDrops.index(of: cellItem) {
			collection.selectItems(at: [IndexPath(item: index, section: 0)], scrollPosition: [])
		}
		guard let item = lockedSelectedItems.first else { return }

		let a = NSAlert()
		a.messageText = "Remove Lock"
		a.informativeText = "Please enter the password you provided when locking this item."
		a.addButton(withTitle: "Remove Lock")
		a.addButton(withTitle: "Cancel")
		let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 24))
		input.placeholderString = "Password"
		a.accessoryView = input
		a.window.initialFirstResponder = input
		a.beginSheetModal(for: view.window!) { [weak self] response in
			if response.rawValue == 1000 {
				let text = input.stringValue
				if item.lockPassword == sha1(text) {
					item.lockPassword = nil
					item.lockHint = nil
					item.needsUnlock = false
					item.markUpdated()
					Model.save()
				} else {
					self?.removeLock(sender)
				}
			}
		}
	}

	func addCellToSelection(_ sender: DropCell) {
		if let cellItem = sender.representedObject as? ArchivedDropItem, let index = Model.filteredDrops.index(of: cellItem) {
			let newIp = IndexPath(item: index, section: 0)
			if !collection.selectionIndexPaths.contains(newIp) {
				collection.selectionIndexPaths = [newIp]
			}
		}
	}

	@objc func createLock(_ sender: Any?) {
		guard let item = actionableSelectedItems.first else { return }

		if item.isLocked && !item.needsUnlock {
			item.needsUnlock = true
			item.postModified()
			return
		}

		let a = NSAlert()
		a.messageText = "Lock Item"
		a.informativeText = "Please enter a password to use for unlocking this item, and an optional hint or description to display on the locked item."
		a.addButton(withTitle: "Lock")
		a.addButton(withTitle: "Cancel")
		let password = NSSecureTextField(frame: NSRect(x: 0, y: 32, width: 290, height: 24))
		password.placeholderString = "Password"
		let hint = NSTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 24))
		hint.placeholderString = "Hint or description"
		hint.stringValue = item.displayText.0 ?? ""
		let input = NSView(frame:  NSRect(x: 0, y: 0, width: 290, height: 56))
		input.addSubview(password)
		input.addSubview(hint)
		a.accessoryView = input
		a.window.initialFirstResponder = password
		a.beginSheetModal(for: view.window!) { [weak self] response in
			if response.rawValue == 1000 {
				let text = password.stringValue
				if !text.isEmpty {
					item.needsUnlock = true
					item.lockPassword = sha1(text)
					item.lockHint = hint.stringValue.isEmpty ? nil : hint.stringValue
					Model.save()
				} else {
					self?.createLock(sender)
				}
			}
		}
	}

	@objc func unlock(_ sender: Any?) {
		guard let item = lockedSelectedItems.first else { return }

		let a = NSAlert()
		a.messageText = "Access Locked Item"
		a.informativeText = "Please enter the password you provided when locking this item."
		a.addButton(withTitle: "Unlock")
		a.addButton(withTitle: "Cancel")
		let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 24))
		input.placeholderString = "Password"
		a.accessoryView = input
		a.window.initialFirstResponder = input
		a.beginSheetModal(for: view.window!) { [weak self] response in
			if response.rawValue == 1000 {
				let text = input.stringValue
				if item.lockPassword == sha1(text) {
					item.needsUnlock = false
					item.postModified()
				} else {
					self?.unlock(sender)
				}
			}
		}
	}

	func lockUnlockedItems() {
		for i in Model.drops where i.isLocked && !i.needsUnlock {
			i.needsUnlock = true
			i.postModified()
		}
	}

	@objc func info(_ sender: Any?) {
		let g = NSPasteboard.general
		g.clearContents()
		for item in actionableSelectedItems {
			performSegue(withIdentifier: NSStoryboardSegue.Identifier("showDetail"), sender: item)
		}
	}

	private var labelController: LabelSelectionViewController?
	@objc func showLabels(_ sender: Any?) {
		if let l = labelController {
			labelController = nil
			l.dismiss(nil)
		} else {
			performSegue(withIdentifier: NSStoryboardSegue.Identifier("showLabels"), sender: nil)
		}
	}

	@objc func showPreferences(_ sender: Any?) {
		performSegue(withIdentifier: NSStoryboardSegue.Identifier("showPreferences"), sender: nil)
	}

	@objc func open(_ sender: Any?) {
		let g = NSPasteboard.general
		g.clearContents()
		for item in actionableSelectedItems {
			item.tryOpen(from: self)
		}
	}

	@objc func copy(_ sender: Any?) {
		let g = NSPasteboard.general
		g.clearContents()
		for item in actionableSelectedItems {
			if let pi = item.pasteboardItem {
				g.writeObjects([pi])
			}
		}
	}

	@objc func moveToTop(_ sender: Any?) {
		for item in actionableSelectedItems {
			if let i = Model.drops.index(of: item) {
				Model.drops.remove(at: i)
				Model.drops.insert(item, at: 0)
			}
		}
		Model.forceUpdateFilter(signalUpdate: false)
		reloadData()
		Model.save()
	}

	@objc func delete(_ sender: Any?) {
		let items = actionableSelectedItems
		if !items.isEmpty {
			if PersistedOptions.unconfirmedDeletes {
				ViewController.shared.deleteRequested(for: items)
			} else {
				let a = NSAlert()
				a.messageText = items.count > 1 ? "Are you sure you want to delete these \(items.count) items?" : "Are you sure you want to delete this item?"
				a.addButton(withTitle: "Delete")
				a.addButton(withTitle: "Cancel")
				a.showsSuppressionButton = true
				a.suppressionButton?.title = "Don't ask me again"
				a.beginSheetModal(for: view.window!) { response in
					if response.rawValue == 1000 {
						ViewController.shared.deleteRequested(for: items)
						if let s = a.suppressionButton, s.integerValue > 0 {
							PersistedOptions.unconfirmedDeletes = true
						}
					}
				}
			}
		}
	}

	@objc func paste(_ sender: Any?) {
		addItems(from: NSPasteboard.general, at: IndexPath(item: 0, section: 0), overrides: nil)
	}

	private var actionableSelectedItems: [ArchivedDropItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = Model.filteredDrops[$0.item]
			return item.needsUnlock ? nil : item
		}
	}

	private var lockedSelectedItems: [ArchivedDropItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = Model.filteredDrops[$0.item]
			return item.isLocked ? item : nil
		}
	}

	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(copy(_:)), #selector(delete(_:)), #selector(shareSelected(_:)), #selector(moveToTop(_:)):
			return actionableSelectedItems.count > 0
		case #selector(paste(_:)):
			return NSPasteboard.general.pasteboardItems?.count ?? 0 > 0
		case #selector(unlock(_:)), #selector(removeLock(_:)):
			return lockedSelectedItems.count == collection.selectionIndexPaths.count && collection.selectionIndexPaths.count == 1
		case #selector(createLock(_:)):
			return lockedSelectedItems.count == 0 && collection.selectionIndexPaths.count == 1
		case #selector(toggleQuickLookPreviewPanel(_:)), #selector(info(_:)), #selector(open(_:)):
			return collection.selectionIndexPaths.count > 0
		default:
			return true
		}
	}

	@objc func toggleQuickLookPreviewPanel(_ sender: Any?) {
		if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
			QLPreviewPanel.shared().orderOut(nil)
		} else {
			QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
		}
	}

	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: nil)
		switch segue.identifier?.rawValue {
		case "showDetail":
			if let item = sender as? ArchivedDropItem,
				let window = segue.destinationController as? NSWindowController,
				let d = window.contentViewController as? DetailController {
				d.representedObject = item
			}

		case "showLabels":
			labelController = segue.destinationController as? LabelSelectionViewController

		default: break
		}
	}

	private func updateEmptyView() {
		if Model.drops.count == 0 && emptyView.alphaValue < 1 {
			emptyView.animator().alphaValue = 1

		} else if emptyView.alphaValue > 0, Model.drops.count > 0 {
			emptyView.animator().alphaValue = 0
		}
	}

	private func blurb(_ text: String) {
		emptyLabel.alphaValue = 0
		emptyLabel.stringValue = text
		emptyLabel.animator().alphaValue = 1
		DispatchQueue.main.asyncAfter(deadline: .now()+3) { [weak self] in
			self?.emptyLabel.animator().alphaValue = 0
		}
	}

	func showIAPPrompt(title: String, subtitle: String,
					   actionTitle: String? = nil, actionAction: (()->Void)? = nil,
					   destructiveTitle: String? = nil, destructiveAction: (()->Void)? = nil,
					   cancelTitle: String? = nil) {

		assert(Thread.isMainThread)

		if Model.isFiltering {
			ViewController.shared.resetSearch(andLabels: true)
		}

		let a = NSAlert()
		a.messageText = title
		a.informativeText = subtitle
		if let cancelTitle = cancelTitle {
			a.addButton(withTitle: cancelTitle)
		}
		if let actionTitle = actionTitle {
			a.addButton(withTitle: actionTitle)
		}
		if let destructiveTitle = destructiveTitle {
			a.addButton(withTitle: destructiveTitle)
		}
		a.beginSheetModal(for: view.window!) { response in
			switch response.rawValue {
			case 1001:
				actionAction?()
			case 1002:
				destructiveAction?()
			default:
				break
			}
		}
	}

	override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
		return collection.selectionIndexPaths.count > 0
	}

	private var previewPanel: QLPreviewPanel?
	override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
		previewPanel = panel
		panel.delegate = self
		panel.dataSource = self
	}

	override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
		previewPanel = nil
	}

	func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
		return collection.selectionIndexPaths.count
	}

	func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
		let index = collection.selectionIndexPaths.sorted()[index].item
		for typeItem in Model.filteredDrops[index].typeItems {
			if typeItem.canPreview {
				return typeItem.quickLookItem
			}
		}
		return nil
	}

	func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
		if event.type == .keyDown {
			collection.keyDown(with: event)
			return true
		}
		return false
	}
}
