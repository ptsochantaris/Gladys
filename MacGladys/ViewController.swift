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

func genericAlert(title: String, message: String?, windowOverride: NSWindow? = nil, completion: (()->Void)? = nil) {

	var finalVC: NSViewController = ViewController.shared
	while let newVC = finalVC.presentedViewControllers?.first(where: { $0.view.window != nil }) {
		finalVC = newVC
	}

	let window = windowOverride ?? finalVC.view.window!

	let a = NSAlert()
	a.messageText = title
	if let message = message {
		a.informativeText = message
	}
	a.beginSheetModal(for: window) { _ in
		completion?()
	}
}

final class WindowController: NSWindowController, NSWindowDelegate {
	func windowWillClose(_ notification: Notification) {
		Model.lockUnlockedItems()
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
			ViewController.shared.hideLabels()
		}
	}

	func windowDidEndLiveResize(_ notification: Notification) {
		ViewController.shared.itemView.reloadData()
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
		ViewController.shared.updateTranslucentMode()
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

final class MainCollectionView: NSCollectionView, NSServicesMenuRequestor {
	override func keyDown(with event: NSEvent) {
		if event.charactersIgnoringModifiers == " " {
			ViewController.shared.toggleQuickLookPreviewPanel(self)
		} else {
			super.keyDown(with: event)
		}
	}

	var actionableSelectedItems: [ArchivedDropItem] {
		return selectionIndexPaths.compactMap {
			let item = Model.filteredDrops[$0.item]
			return item.needsUnlock ? nil : item
		}
	}

	private var selectedTypes = Set<NSPasteboard.PasteboardType>()

	override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
		if returnType == nil, let s = sendType, selectedTypes.contains(s) {
			return self
		}
		return super.validRequestor(forSendType: sendType, returnType: returnType)
	}

	func updateServices() {
		var sendTypes = Set<NSPasteboard.PasteboardType>()

		for item in actionableSelectedItems {
			for t in item.typeItems.map({ NSPasteboard.PasteboardType($0.typeIdentifier) }) {
				sendTypes.insert(t)
			}
		}
		selectedTypes = sendTypes
		NSApplication.shared.registerServicesMenuSendTypes(Array(sendTypes), returnTypes: [])
	}

	func readSelection(from pboard: NSPasteboard) -> Bool {
		return false
	}

	func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
		let objectsToWrite = actionableSelectedItems.compactMap { $0.pasteboardItem }
		if objectsToWrite.isEmpty {
			return false
		} else {
			pboard.writeObjects(objectsToWrite)
			return true
		}
	}

	override func selectItems(at indexPaths: Set<IndexPath>, scrollPosition: NSCollectionView.ScrollPosition) {
		super.selectItems(at: indexPaths, scrollPosition: scrollPosition)
		updateServices()
	}
}

final class ViewController: NSViewController, NSCollectionViewDelegate, NSCollectionViewDataSource, ItemIngestionDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSMenuItemValidation, NSSearchFieldDelegate {

	@IBOutlet private weak var collection: MainCollectionView!

	static var shared: ViewController! = nil

	private static let dropCellId = NSUserInterfaceItemIdentifier("DropCell")

	static let labelColor = NSColor.labelColor

	static var tintColor: NSColor {
		if #available(OSX 10.14, *) {
			switch ViewController.shared.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) {
			case NSAppearance.Name.darkAqua:
				return #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)
			default:
				return #colorLiteral(red: 0.5764705882, green: 0.09411764706, blue: 0.07058823529, alpha: 1)
			}
		} else {
			return #colorLiteral(red: 0.5764705882, green: 0.09411764706, blue: 0.07058823529, alpha: 1)
		}
	}

	@IBOutlet private weak var searchHolder: NSView!
	@IBOutlet private weak var searchBar: NSSearchField!

	@IBOutlet private weak var emptyView: NSImageView!
	@IBOutlet private weak var emptyLabel: NSTextField!

	@IBOutlet private weak var topBackground: NSVisualEffectView!
	@IBOutlet private weak var titleBarBackground: NSView!

	@IBOutlet private weak var translucentView: NSVisualEffectView!

	override func viewWillAppear() {
		if let w = view.window {
			updateCellSize(from: w.frame.size)
		}
		updateTitle()
		AppDelegate.shared?.updateMenubarIconMode(showing: true, forceUpdateMenu: false)

		super.viewWillAppear()

		if PersistedOptions.hideTitlebar {
			hideTitlebar()
		}
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		updateAlwaysOnTop()
	}

	private func updateAlwaysOnTop() {
		guard let w = view.window else { return }
		if PersistedOptions.alwaysOnTop {
			w.level = .modalPanel
		} else {
			w.level = .normal
		}
	}

	override func viewDidDisappear() {
		super.viewDidDisappear()
		AppDelegate.shared?.updateMenubarIconMode(showing: false, forceUpdateMenu: false)
	}

	var itemView: MainCollectionView {
		return collection
	}

	private func reloadData(inserting: [IndexPath]? = nil, deleting: [IndexPath]? = nil) {
		let selectedUUIDS = collection.selectionIndexPaths.compactMap { collection.item(at: $0) }.compactMap { $0.representedObject as? ArchivedDropItem }.map { $0.uuid }
		if let inserting = inserting {
			collection.deselectAll(nil)
			collection.animator().insertItems(at: Set(inserting))
		} else if let deleting = deleting {
			collection.deselectAll(nil)
			collection.animator().deleteItems(at: Set(deleting))
		} else {
			collection.animator().reloadData()
		}
		var index = 0
		var indexSet = Set<IndexPath>()
		for i in Model.filteredDrops {
			if selectedUUIDS.contains(i.uuid) {
				indexSet.insert(IndexPath(item: index, section: 0))
			}
			index += 1
		}
		if !indexSet.isEmpty {
			collection.selectItems(at: indexSet, scrollPosition: .centeredHorizontally)
		}
	}

	func updateTranslucentMode() {
		guard let l = view.window?.contentView?.layer else { return }
		if PersistedOptions.translucentMode {
			translucentView.isHidden = false
			l.contents = nil
		} else {
			translucentView.isHidden = true
			let i = #imageLiteral(resourceName: "paper")
			i.resizingMode = .tile
			l.contents = i
			l.contentsGravity = .resize
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
		showSearch = false

		collection.registerForDraggedTypes([NSPasteboard.PasteboardType(kUTTypeItem as String), NSPasteboard.PasteboardType(kUTTypeContent as String)])
		updateDragOperationIndicators()

		Model.reloadDataIfNeeded()

		let n = NotificationCenter.default

		let a1 = n.addObserver(forName: .ExternalDataUpdated, object: nil, queue: .main) { [weak self] _ in
			self?.detectExternalDeletions()
			Model.rebuildLabels()
			Model.forceUpdateFilter(signalUpdate: false) // refresh filtered items
			self?.updateEmptyView()
			self?.reloadData()
			self?.postSave()
		}

		let a2 = n.addObserver(forName: .SaveComplete, object: nil, queue: .main) { [weak self] _ in
			self?.updateTitle()
			self?.reloadData()
			self?.postSave()
		}

		let a3 = n.addObserver(forName: .ItemCollectionNeedsDisplay, object: nil, queue: .main) { [weak self] _ in
			self?.updateTitle()
			self?.reloadData()
		}

		let a4 = n.addObserver(forName: .CloudManagerStatusChanged, object: nil, queue: .main) { [weak self] _ in
			self?.updateTitle()
		}

		let a5 = n.addObserver(forName: .LabelSelectionChanged, object: nil, queue: .main) { [weak self] _ in
			self?.collection.deselectAll(nil)
			Model.forceUpdateFilter(signalUpdate: true)
			self?.updateTitle()
		}

		let a6 = n.addObserver(forName: .AcceptStarting, object: nil, queue: .main) { [weak self] _ in
			self?.startProgress(for: nil, titleOverride: "Accepting Share...")
		}

		let a7 = n.addObserver(forName: .AcceptEnding, object: nil, queue: .main) { [weak self] _ in
			self?.endProgress()
		}

		let a8  = n.addObserver(forName: .AlwaysOnTopChanged, object: nil, queue: .main) { [weak self] _ in
			self?.updateAlwaysOnTop()
		}

		DistributedNotificationCenter.default.addObserver(self, selector: #selector(interfaceModeChanged(sender:)), name: NSNotification.Name(rawValue: "AppleInterfaceThemeChangedNotification"), object: nil)

		observers = [a1, a2, a3, a4, a5, a6, a7, a8]

		if CloudManager.syncSwitchedOn {
			CloudManager.sync { _ in }
		}

		updateTitle()
		postSave()

		if Model.drops.count == 0 {
			blurb("Ready! Drop me stuff.")
		}
	}

	@objc private func interfaceModeChanged(sender: NSNotification) {
		imageCache.removeAllObjects()
		collection.reloadData()
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

		let items = collection.actionableSelectedItems

		if let syncStatus = CloudManager.syncProgressString {
			view.window?.title = "\(title) — \(syncStatus)"

		} else if items.count > 1 {
			let selectedItems = items.map { $0.uuid }
			let size = Model.sizeForItems(uuids: selectedItems)
			let sizeString = diskSizeFormatter.string(fromByteCount: size)
			let selectedReport = "Selected \(selectedItems.count) Items: \(sizeString)"
			view.window?.title = "\(title) — \(selectedReport)"

		} else {
			view.window?.title = title
		}

		collection.updateServices()
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

	@objc private func toggleTitlebar(_ sender: Any?) {
		guard let w = view.window else { return }
		switch w.titleVisibility {
		case .hidden:
			showTitlebar()
			PersistedOptions.hideTitlebar = false
		case .visible:
			hideTitlebar()
			PersistedOptions.hideTitlebar = true
		}
	}

	private func showTitlebar() {
		if !titleBarBackground.isHidden { return }
		guard let w = view.window else { return }
		w.titleVisibility = .visible
		titleBarBackground.isHidden = false
		w.standardWindowButton(.closeButton)?.isHidden = false
		w.standardWindowButton(.miniaturizeButton)?.isHidden = false
		w.standardWindowButton(.zoomButton)?.isHidden = false
		updateScrollviewInsets()
	}

	private func hideTitlebar() {
		if titleBarBackground.isHidden { return }
		guard let w = view.window else { return }
		w.titleVisibility = .hidden
		titleBarBackground.isHidden = true
		w.standardWindowButton(.closeButton)?.isHidden = true
		w.standardWindowButton(.miniaturizeButton)?.isHidden = true
		w.standardWindowButton(.zoomButton)?.isHidden = true
		updateScrollviewInsets()
	}

	private func postSave() {
		for i in Model.itemsToReIngest {
			i.reIngest(delegate: self)
		}
		updateEmptyView()
	}

	func itemIngested(item: ArchivedDropItem) {

		var loadingError = false
		if let (errorPrefix, error) = item.loadingError {
			loadingError = true
			genericAlert(title: "Some data from \(item.displayTitleOrUuid) could not be imported", message: errorPrefix + error.finalDescription)
		}

		item.needsReIngest = false

		if let i = Model.filteredDrops.index(of: item) {
			let ip = IndexPath(item: i, section: 0)
			collection.reloadItems(at: [ip])
			item.reIndex()
		} else {
			item.reIndex {
				DispatchQueue.main.async { // if item is still invisible after re-indexing, let the user know
					if !Model.forceUpdateFilter(signalUpdate: true) && !loadingError {
						if item.createdAt == item.updatedAt && !item.loadingAborted {
							genericAlert(title: "Item(s) Added", message: nil)
						}
					}
				}
			}
		}

		if Model.doneIngesting {
			Model.save()
		} else {
			Model.commitItem(item: item)
		}
	}

	func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
		if collection.selectionIndexPaths.count > 0 && QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
			QLPreviewPanel.shared().reloadData()
		}
		updateTitle()
	}

	func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
		updateTitle()
	}

	func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
		return Model.filteredDrops.count
	}

	func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
		let i = collectionView.makeItem(withIdentifier: ViewController.dropCellId, for: indexPath)
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
		DistributedNotificationCenter.default.removeObserver(self)
	}

	@objc func shareSelected(_ sender: Any?) {
		guard let itemToShare = collection.actionableSelectedItems.first,
			let i = Model.filteredDrops.index(of: itemToShare),
			let cell = collection.item(at: IndexPath(item: i, section: 0))
			else { return }

		collection.deselectAll(nil)
		collection.selectItems(at: [IndexPath(item: i, section: 0)], scrollPosition: [])
		let p = NSSharingServicePicker(items: [itemToShare.itemProviderForSharing])
		let f = cell.view.frame
		let centerFrame = NSRect(origin: CGPoint(x: f.midX-1, y: f.midY-1), size: CGSize(width: 2, height: 2))
		DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
			p.show(relativeTo: centerFrame, of: self.collection, preferredEdge: .minY)
		}
	}

	@IBAction private func searchDoneSelected(_ sender: NSButton) {
		resetSearch(andLabels: false)
	}

	private func resetSearch(andLabels: Bool) {
		searchBar.stringValue = ""
		showSearch = false
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

	@IBAction private func findSelected(_ sender: NSMenuItem) {
		if showSearch {
			resetSearch(andLabels: false)
		} else {
			showSearch = true
			view.window?.makeFirstResponder(searchBar)
		}
	}

	func controlTextDidChange(_ obj: Notification) {
		collection.selectionIndexes = []
		updateSearch()
	}

	private func updateSearch() {
		let s = searchBar.stringValue
		Model.filter = s.isEmpty ? nil : s
	}

	func highlightItem(with identifier: String, andOpen: Bool = false, andPreview: Bool = false, focusOnChild: String? = nil) {
		// focusOnChild ignored for now
		resetSearch(andLabels: true)
		if let item = Model.item(uuid: identifier) {
			if let i = Model.drops.index(of: item) {
				let ip = IndexPath(item: i, section: 0)
				collection.scrollToItems(at: [ip], scrollPosition: .centeredVertically)
				collection.selectionIndexes = IndexSet(integer: i)
				if andOpen {
					info(nil)
				} else if andPreview {
					if !(previewPanel?.isVisible ?? false) {
						ViewController.shared.toggleQuickLookPreviewPanel(self)
					}
				}
			}
		}
	}

	private var showSearch: Bool = false {
		didSet {
			searchHolder.isHidden = !showSearch
			updateScrollviewInsets()
		}
	}

	private func updateScrollviewInsets() {
		DispatchQueue.main.async {
			guard let scrollView = self.collection.enclosingScrollView else { return }
			let offset = scrollView.contentView.bounds.origin.y
			let topHeight = self.topBackground.frame.size.height
			scrollView.contentInsets = NSEdgeInsets(top: topHeight, left: 0, bottom: 0, right: 0)
			if offset <= 0 {
				DispatchQueue.main.asyncAfter(deadline: .now()+0.01) {
					scrollView.documentView?.scroll(CGPoint(x: 0, y: -topHeight))
				}
			}
		}
	}

	func startSearch(initialText: String) {
		showSearch = true
		searchBar.stringValue = initialText
		updateSearch()
	}

	func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
		return Model.filteredDrops[indexPath.item].pasteboardItem
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
		if let s = draggingInfo.draggingSource as? NSCollectionView, s == collectionView, let dip = draggingIndexPaths {

			draggingIndexPaths = nil
			if let firstDip = dip.first, firstDip == indexPath {
				return false
			}

			var destinationIndex = Model.nearestUnfilteredIndexForFilteredIndex(indexPath.item)
			if destinationIndex >= Model.drops.count {
				destinationIndex = Model.drops.count - 1
			}

			var indexPath = indexPath
			if indexPath.item >= Model.filteredDrops.count {
				indexPath.item = Model.filteredDrops.count - 1
			}

			for draggingIndexPath in dip.sorted(by: { $0.item > $1.item }) {
				let sourceItem = Model.filteredDrops[draggingIndexPath.item]
				let sourceIndex = Model.drops.index(of: sourceItem)!
				Model.drops.remove(at: sourceIndex)
				Model.drops.insert(sourceItem, at: destinationIndex)
				collection.animator().moveItem(at: draggingIndexPath, to: indexPath)
				collection.deselectAll(nil)
			}
			Model.forceUpdateFilter(signalUpdate: false)
			Model.save()
			return true
		} else {
			let p = draggingInfo.draggingPasteboard
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

		return addItems(itemProviders: itemProviders, name: pasteBoard.name.rawValue, indexPath: indexPath, overrides: overrides)
	}

	@discardableResult
	func addItems(itemProviders: [NSItemProvider], name: String?, indexPath: IndexPath, overrides: ImportOverrides?) -> Bool {
		if IAPManager.shared.checkInfiniteMode(for: itemProviders.count) {
			return false
		}

		var insertedIndexPaths = [IndexPath]()
		var count = 0
		for provider in itemProviders {
			for newItem in ArchivedDropItem.importData(providers: [provider], delegate: self, overrides: overrides, pasteboardName: name) {

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

		if count > 0 {
			if Model.forceUpdateFilter(signalUpdate: false) {
				reloadData(inserting: insertedIndexPaths)
			}
			return true
		} else {
			return false
		}
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
		addItems(itemProviders: providers, name: nil, indexPath: IndexPath(item: 0, section: 0), overrides: nil)
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
		let items = removableLockSelectedItems
		let plural = items.count > 1
		let actionName = "Remove Lock" + (plural ? "s" : "")

		let a = NSAlert()
		a.messageText = actionName
		a.informativeText = plural ? "Please enter the password you provided when locking these items." : "Please enter the password you provided when locking this item."
		a.addButton(withTitle: actionName)
		a.addButton(withTitle: "Cancel")
		let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 24))
		input.placeholderString = "Password"
		a.accessoryView = input
		a.window.initialFirstResponder = input
		a.beginSheetModal(for: view.window!) { [weak self] response in
			if response.rawValue == 1000 {
				let text = input.stringValue
				let hash = sha1(text)
				var successCount = 0
				for item in items where item.lockPassword == hash {
					item.lockPassword = nil
					item.lockHint = nil
					item.needsUnlock = false
					item.markUpdated()
					item.reIndex()
					successCount += 1
				}
				if successCount == 0 {
					self?.removeLock(sender)
				} else {
					Model.save()
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

		let instaLock = lockableSelectedItems.filter { $0.isLocked && !$0.needsUnlock }
		for item in instaLock {
			item.needsUnlock = true
			item.postModified()
		}

		let items = lockableSelectedItems
		if items.isEmpty {
			return
		}

		let message = items.count > 1
		? "Please provide the password you will use to unlock these items. You can also provide an optional label to display while the items are locked."
		: "Please provide the password you will use to unlock this item. You can also provide an optional label to display while the item is locked."

		let hintText = (items.count == 1) ? items.first?.displayText.0 : nil

		let a = NSAlert()
		a.messageText = items.count > 1 ? "Lock Items" : "Lock Item"
		a.informativeText = message
		a.addButton(withTitle: "Lock")
		a.addButton(withTitle: "Cancel")
		let password = NSSecureTextField(frame: NSRect(x: 0, y: 32, width: 290, height: 24))
		password.placeholderString = "Password"
		let hint = NSTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 24))
		hint.placeholderString = "Hint or description"
		hint.stringValue = hintText ?? ""
		let input = NSView(frame:  NSRect(x: 0, y: 0, width: 290, height: 56))
		input.addSubview(password)
		input.addSubview(hint)
		password.nextKeyView = hint
		hint.nextKeyView = password
		a.accessoryView = input
		a.window.initialFirstResponder = password
		a.beginSheetModal(for: view.window!) { [weak self] response in
			if response.rawValue == 1000 {
				let text = password.stringValue
				if !text.isEmpty {
					let hashed = sha1(text)
					for item in items {
						item.needsUnlock = true
						item.lockPassword = hashed
						item.lockHint = hint.stringValue.isEmpty ? nil : hint.stringValue
						item.markUpdated()
						item.reIndex()
					}
					Model.save()
				} else {
					self?.createLock(sender)
				}
			}
		}
	}

	@objc func unlock(_ sender: Any?) {
		let items = unlockableSelectedItems
		let plural = items.count > 1

		let a = NSAlert()
		a.messageText = "Access Locked Item" + (plural ? "s" : "")
		a.informativeText = plural ? "Please enter the password you provided when locking these items." : "Please enter the password you provided when locking this item."
		a.addButton(withTitle: "Unlock")
		a.addButton(withTitle: "Cancel")
		let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 24))
		input.placeholderString = "Password"
		a.accessoryView = input
		a.window.initialFirstResponder = input
		a.beginSheetModal(for: view.window!) { [weak self] response in
			if response.rawValue == 1000 {
				let text = input.stringValue
				var successCount = 0
				let hashed = sha1(text)
				for item in items where item.lockPassword == hashed {
					item.needsUnlock = false
					item.postModified()
					successCount += 1
				}
				if successCount == 0 {
					self?.unlock(sender)
				}
			}
		}
	}

	@objc func info(_ sender: Any?) {
		let g = NSPasteboard.general
		g.clearContents()
		for item in collection.actionableSelectedItems {
			let uuid = item.uuid
			if DetailController.showingUUIDs.contains(uuid) {
				NotificationCenter.default.post(name: .ForegroundDisplayedItem, object: uuid)
			} else {
				performSegue(withIdentifier: NSStoryboardSegue.Identifier("showDetail"), sender: item)
			}
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
	func hideLabels() {
		if labelController != nil {
			showLabels(nil)
		}
	}

	@objc func showPreferences(_ sender: Any?) {
		performSegue(withIdentifier: NSStoryboardSegue.Identifier("showPreferences"), sender: nil)
	}

	@objc func editLabels(_ sender: Any?) {
		performSegue(withIdentifier: NSStoryboardSegue.Identifier("editLabels"), sender: nil)
	}

	@objc func open(_ sender: Any?) {
		let g = NSPasteboard.general
		g.clearContents()
		for item in collection.actionableSelectedItems {
			item.tryOpen(from: self)
		}
	}

	@objc func copy(_ sender: Any?) {
		let g = NSPasteboard.general
		g.clearContents()
		for item in collection.actionableSelectedItems {
			if let pi = item.pasteboardItem {
				g.writeObjects([pi])
			}
		}
	}

	@objc func moveToTop(_ sender: Any?) {
		for item in collection.actionableSelectedItems {
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
		let items = collection.actionableSelectedItems
		if items.isEmpty { return }
		if PersistedOptions.unconfirmedDeletes {
			ViewController.shared.deleteRequested(for: items)
		} else {
			let a = NSAlert()
			if items.count == 1, let first = items.first, first.shareMode == .sharing {
				a.messageText = "You are sharing this item"
				a.informativeText = "Deleting it will remove it from others' collections too."
			} else {
				a.messageText = items.count > 1 ? "Are you sure you want to delete these \(items.count) items?" : "Are you sure you want to delete this item?"
			}
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

	@objc func paste(_ sender: Any?) {
		addItems(from: NSPasteboard.general, at: IndexPath(item: 0, section: 0), overrides: nil)
	}

	var lockableSelectedItems: [ArchivedDropItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = Model.filteredDrops[$0.item]
			let isLocked = item.isLocked
			let canBeLocked = !isLocked || (isLocked && !item.needsUnlock)
			return (!canBeLocked || item.isImportedShare) ? nil : item
		}
	}

	var selectedItems: [ArchivedDropItem] {
		return collection.selectionIndexPaths.map {
			Model.filteredDrops[$0.item]
		}
	}

	var removableLockSelectedItems: [ArchivedDropItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = Model.filteredDrops[$0.item]
			return (!item.isLocked || item.isImportedShare) ? nil : item
		}
	}

	var unlockableSelectedItems: [ArchivedDropItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = Model.filteredDrops[$0.item]
			return (!item.needsUnlock || item.isImportedShare) ? nil : item
		}
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(copy(_:)), #selector(shareSelected(_:)), #selector(moveToTop(_:)), #selector(info(_:)), #selector(open(_:)), #selector(delete(_:)), #selector(editLabels(_:)):
			return !collection.actionableSelectedItems.isEmpty

		case #selector(paste(_:)):
			return NSPasteboard.general.pasteboardItems?.count ?? 0 > 0

		case #selector(unlock(_:)):
			return !unlockableSelectedItems.isEmpty

		case #selector(removeLock(_:)):
			return !removableLockSelectedItems.isEmpty

		case #selector(createLock(_:)):
			return !lockableSelectedItems.isEmpty

		case #selector(toggleQuickLookPreviewPanel(_:)):
			let selectedItems = collection.actionableSelectedItems
			if selectedItems.count > 1 {
				menuItem.title = "Quick Look Selected Items"
				return true
			} else if let first = selectedItems.first {
				menuItem.title = "Quick Look \"\(first.displayTitleOrUuid.truncateWithEllipses(limit: 30))\""
				return true
			} else {
				menuItem.title = "Quick Look"
				return false
			}

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
		switch segue.identifier {
		case "showDetail":
			if let item = sender as? ArchivedDropItem,
				let window = segue.destinationController as? NSWindowController,
				let d = window.contentViewController as? DetailController {
				d.representedObject = item
			}

		case "showLabels":
			labelController = segue.destinationController as? LabelSelectionViewController

		case "editLabels":
			if let destination = segue.destinationController as? LabelEditorViewController {
				destination.selectedItems = collection.actionableSelectedItems.map { $0.uuid }
			}

		case "showProgress":
			progressController = segue.destinationController as? ProgressViewController

		default: break
		}
	}

	private func updateEmptyView() {
		if Model.drops.count == 0 && emptyView.alphaValue < 1 {
			emptyView.animator().alphaValue = 1

		} else if emptyView.alphaValue > 0, Model.drops.count > 0 {
			emptyView.animator().alphaValue = 0
			emptyLabel.animator().alphaValue = 0
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

	//////////////////////////////////////////////////// Quicklook

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
		return Model.filteredDrops[index].previewableTypeItem?.quickLookItem
	}

	func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
		if event.type == .keyDown {
			collection.keyDown(with: event)
			return true
		}
		return false
	}

	func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
		guard let qlItem = item as? ArchivedDropItemType.PreviewItem else { return .zero }
		if let drop = Model.item(uuid: qlItem.parentUuid), let index = Model.filteredDrops.index(of: drop) {
			let frameRealativeToCollection = collection.frameForItem(at: index)
			let frameRelativeToWindow = collection.convert(frameRealativeToCollection, to: nil)
			let frameRelativeToScreen = view.window!.convertToScreen(frameRelativeToWindow)
			return frameRelativeToScreen
		}
		return .zero
	}

	func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
		let visibleCells = collection.visibleItems()
		if let qlItem = item as? ArchivedDropItemType.PreviewItem,
			let parentUuid = Model.typeItem(uuid: qlItem.uuid.uuidString)?.parentUuid,
			let cellIndex = visibleCells.index(where: { ($0.representedObject as? ArchivedDropItem)?.uuid == parentUuid }) {
			return (visibleCells[cellIndex] as? DropCell)?.previewImage
		}
		return nil
	}

	/////////////////////////////////////////// Progress reports

	private var progressController: ProgressViewController?

	func startProgress(for progress: Progress?, titleOverride: String? = nil) {
		if isDisplayingProgress {
			endProgress()
		}
		performSegue(withIdentifier: NSStoryboardSegue.Identifier("showProgress"), sender: self)
		progressController?.startMonitoring(progress: progress, titleOverride: titleOverride)
	}

	var isDisplayingProgress: Bool {
		return progressController != nil
	}

	func endProgress() {
		if let p = progressController {
			p.endMonitoring()
			p.dismiss(p)
			progressController = nil
		}
	}
}
