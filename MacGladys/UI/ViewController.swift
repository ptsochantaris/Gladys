//
//  ViewController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa
import Quartz
import GladysFramework

func genericAlert(title: String, message: String?, windowOverride: NSWindow? = nil, buttonTitle: String = "OK", completion: (()->Void)? = nil) {

	var finalVC: NSViewController = ViewController.shared
	while let newVC = finalVC.presentedViewControllers?.first(where: { $0.view.window != nil }) {
		finalVC = newVC
	}

	let a = NSAlert()
	a.messageText = title
	a.addButton(withTitle: buttonTitle)
	if let message = message {
		a.informativeText = message
	}
    
    if let window = windowOverride ?? finalVC.view.window {
        a.beginSheetModal(for: window) { _ in
            completion?()
        }
    } else {
        a.runModal()
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

	var actionableSelectedItems: [ArchivedItem] {
		return selectionIndexPaths.compactMap {
			let item = Model.sharedFilter.filteredDrops[$0.item]
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
			for t in item.components.map({ NSPasteboard.PasteboardType($0.typeIdentifier) }) {
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
		let objectsToWrite = actionableSelectedItems.compactMap { $0.pasteboardItem(forDrag: false) }
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

final class ViewController: NSViewController, NSCollectionViewDelegate, NSCollectionViewDataSource, QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSMenuItemValidation, NSSearchFieldDelegate, NSTouchBarDelegate {

	@IBOutlet private weak var collection: MainCollectionView!

	static var shared: ViewController!

	private static let dropCellId = NSUserInterfaceItemIdentifier("DropCell")

	@IBOutlet private weak var searchHolder: NSView!
	@IBOutlet private weak var searchBar: NSSearchField!

	@IBOutlet private weak var emptyView: NSImageView!
	@IBOutlet private weak var emptyLabel: NSTextField!

	@IBOutlet private weak var topBackground: NSVisualEffectView!
	@IBOutlet private weak var titleBarBackground: NSView!

	@IBOutlet private weak var translucentView: NSVisualEffectView!

	override func viewWillAppear() {
		handleLayout()
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
    
    private func insertItems(count: Int) {
        collection.deselectAll(nil)
        let ips = (0 ..< count).map { IndexPath(item: $0, section: 0) }
        collection.animator().insertItems(at: Set(ips))
    }
    
    var touchBarScrubber: GladysTouchBarScrubber?

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

        Model.setup()

		let n = NotificationCenter.default

		let a1 = n.addObserver(forName: .ModelDataUpdated, object: nil, queue: .main) { [weak self] notification in
			Model.detectExternalChanges()
            self?.updateEmptyView()
            self?.modelDataUpdate(notification)
		}

		let a3 = n.addObserver(forName: .ItemCollectionNeedsDisplay, object: nil, queue: .main) { [weak self] _ in
			self?.updateTitle()
            self?.collection.animator().reloadData()
		}

		let a4 = n.addObserver(forName: .CloudManagerStatusChanged, object: nil, queue: .main) { [weak self] _ in
			self?.updateTitle()
		}

		let a5 = n.addObserver(forName: .LabelSelectionChanged, object: nil, queue: .main) { [weak self] _ in
			self?.collection.deselectAll(nil)
			Model.sharedFilter.updateFilter(signalUpdate: true)
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

		let a9 = n.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
			self?.handleLayout()
		}
                
        let a11 = n.addObserver(forName: .IngestComplete, object: nil, queue: .main) { [weak self] notification in
            guard let item = notification.object as? ArchivedItem else { return }
            self?.itemIngested(item)
        }
        
        let a12 = n.addObserver(forName: .HighlightItemRequested, object: nil, queue: .main) { [weak self] notification in
            guard let request = notification.object as? HighlightRequest else { return }
            self?.highlightItem(with: request)
        }
        
		DistributedNotificationCenter.default.addObserver(self, selector: #selector(interfaceModeChanged(sender:)), name: NSNotification.Name(rawValue: "AppleInterfaceThemeChangedNotification"), object: nil)

		observers = [a1, a3, a4, a5, a6, a7, a8, a9, a11, a12]

		if CloudManager.syncSwitchedOn {
			CloudManager.sync { _ in }
		}

		updateTitle()
        updateEmptyView()
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
		if Model.sharedFilter.isFilteringLabels {
			title = Model.sharedFilter.enabledLabelsForTitles.joined(separator: ", ")
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

    private var firstKey = true
	func isKey() {
		if Model.sharedFilter.filteredDrops.isEmpty {
            if firstKey {
                firstKey = false
                blurb(Greetings.openLine)
            } else {
                blurb(Greetings.randomGreetLine)
            }
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
		@unknown default:
			showTitlebar()
			PersistedOptions.hideTitlebar = false
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

    private func itemIngested(_ item: ArchivedItem) {
		if let (errorPrefix, error) = item.loadingError {
			genericAlert(title: "Some data from \(item.displayTitleOrUuid) could not be imported", message: errorPrefix + error.finalDescription)
		}

		if Model.doneIngesting {
			Model.save()
		} else {
			Model.commitItem(item: item)
		}
	}

	func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
		if !collection.selectionIndexPaths.isEmpty && QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
			QLPreviewPanel.shared().reloadData()
		}
		updateTitle()
	}

	func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
		updateTitle()
	}

	func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
		return Model.sharedFilter.filteredDrops.count
	}

	func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
		let i = collectionView.makeItem(withIdentifier: ViewController.dropCellId, for: indexPath)
		i.representedObject = Model.sharedFilter.filteredDrops[indexPath.item]
		return i
	}

	override func viewWillLayout() {
		super.viewWillLayout()
		handleLayout()
	}

	private func handleLayout() {
		guard let window = view.window else { return }

		let scrollbarInset: CGFloat
		if let v = collection.enclosingScrollView?.verticalScroller, v.scrollerStyle == .legacy {
			scrollbarInset = v.frame.width
		} else {
			scrollbarInset = 0
		}

		var currentWidth = window.frame.size.width
		let newMinSize = NSSize(width: 180 + scrollbarInset, height: 180)
		let previousMinSize = window.minSize
		if previousMinSize != newMinSize {
			window.minSize = newMinSize
			if currentWidth < newMinSize.width || currentWidth == previousMinSize.width { // conform to new minimum width as we're already at minimum size
				currentWidth = newMinSize.width
				window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: currentWidth, height: window.frame.height)), display: false)
			}
		}

		let baseSize: CGFloat = 170
		let w = currentWidth - 10 - scrollbarInset
		let columns = (w / baseSize).rounded(.down)
		let leftOver = w.truncatingRemainder(dividingBy: baseSize)
		let s = ((baseSize - 10) + (leftOver / columns)).rounded(.down)
		(collection.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize = NSSize(width: s, height: s)
	}

	deinit {
		for o in observers {
			NotificationCenter.default.removeObserver(o)
		}
		DistributedNotificationCenter.default.removeObserver(self)
	}

	@objc func shareSelected(_ sender: Any?) {
		guard let itemToShare = collection.actionableSelectedItems.first,
			let i = Model.sharedFilter.filteredDrops.firstIndex(of: itemToShare),
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
        findSelected(nil)
	}

	func resetSearch(andLabels: Bool) {
		searchBar.stringValue = ""
		showSearch = false
		updateSearch()

		if andLabels {
			Model.sharedFilter.disableAllLabels()
		}
	}

	@IBAction func findSelected(_ sender: NSMenuItem?) {
		if showSearch {
			resetSearch(andLabels: false)
            DispatchQueue.main.async {
                self.view.window?.makeFirstResponder(self.collection)
            }
		} else {
			showSearch = true
			DispatchQueue.main.async {
				self.view.window?.makeFirstResponder(self.searchBar)
			}
		}
	}

	func controlTextDidChange(_ obj: Notification) {
		collection.selectionIndexes = []
		updateSearch()
	}

	private func updateSearch() {
		let s = searchBar.stringValue
		Model.sharedFilter.filter = s.isEmpty ? nil : s
        updateEmptyView()
	}

    func touchedItem(_ item: ArchivedItem) {
        if let index = Model.sharedFilter.filteredDrops.firstIndex(of: item) {
            let ip = IndexPath(item: index, section: 0)
            collection.scrollToItems(at: [ip], scrollPosition: .centeredVertically)
            collection.selectionIndexes = IndexSet(integer: index)
            
            if let cell = collection.item(at: IndexPath(item: index, section: 0)) as? DropCell {
                cell.actioned(fromTouchbar: true)
            }
        }
    }

    private func highlightItem(with request: HighlightRequest) {
		// focusOnChild ignored for now
		resetSearch(andLabels: true)
        if let item = Model.item(uuid: request.uuid) {
			if let i = Model.drops.firstIndex(of: item) {
				let ip = IndexPath(item: i, section: 0)
				collection.scrollToItems(at: [ip], scrollPosition: .centeredVertically)
				collection.selectionIndexes = IndexSet(integer: i)
                if request.open {
					info(nil)
                } else if request.preview {
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
		return Model.sharedFilter.filteredDrops[indexPath.item].pasteboardItem(forDrag: true)
	}

	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
		return !indexPaths.map { Model.sharedFilter.filteredDrops[$0.item].needsUnlock }.contains(true)
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
				let items = d.map { Model.sharedFilter.filteredDrops[$0.item] }
                Model.delete(items: items)
			}
			draggingIndexPaths = nil
		}
		session.draggingPasteboard.clearContents() // release promise providers
	}

	func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
		if let s = draggingInfo.draggingSource as? NSCollectionView, s == collectionView, let dip = draggingIndexPaths {

			draggingIndexPaths = nil // protect from internal alt-move
			if let firstDip = dip.first, firstDip == indexPath {
				return false
			}

			var destinationIndex = Model.sharedFilter.nearestUnfilteredIndexForFilteredIndex(indexPath.item)
			if destinationIndex >= Model.drops.count {
				destinationIndex = Model.drops.count - 1
			}

			var indexPath = indexPath
			if indexPath.item >= Model.sharedFilter.filteredDrops.count {
				indexPath.item = Model.sharedFilter.filteredDrops.count - 1
			}

			for draggingIndexPath in dip.sorted(by: { $0.item > $1.item }) {
				let sourceItem = Model.sharedFilter.filteredDrops[draggingIndexPath.item]
				let sourceIndex = Model.drops.firstIndex(of: sourceItem)!
				Model.drops.remove(at: sourceIndex)
				Model.drops.insert(sourceItem, at: destinationIndex)
				collection.deselectAll(nil)
			}
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

		return addItems(itemProviders: itemProviders, indexPath: indexPath, overrides: overrides)
	}

	@discardableResult
	func addItems(itemProviders: [NSItemProvider], indexPath: IndexPath, overrides: ImportOverrides?) -> Bool {
		if IAPManager.shared.checkInfiniteMode(for: itemProviders.count) {
			return false
		}

		var inserted = false
		for provider in itemProviders {
			for newItem in ArchivedItem.importData(providers: [provider], overrides: overrides) {

				var modelIndex = indexPath.item
				if Model.sharedFilter.isFiltering {
					modelIndex = Model.sharedFilter.nearestUnfilteredIndexForFilteredIndex(indexPath.item)
					if Model.sharedFilter.isFilteringLabels && !PersistedOptions.dontAutoLabelNewItems {
						newItem.labels = Model.sharedFilter.enabledLabelsForItems
					}
				}
				Model.drops.insert(newItem, at: modelIndex)
                inserted = true
			}
		}

        if inserted {
            Model.sharedFilter.updateFilter(signalUpdate: true)
		}
        return inserted
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
		addItems(itemProviders: providers, indexPath: IndexPath(item: 0, section: 0), overrides: nil)
	}

    private func modelDataUpdate(_ notification: Notification) {
        let parameters = notification.object as? [AnyHashable: Any]
        let savedUUIDs = parameters?["updated"] as? Set<UUID> ?? Set<UUID>()
        let selectedUUIDS = collection.selectionIndexPaths.compactMap { collection.item(at: $0) }.compactMap { $0.representedObject as? ArchivedItem }.map { $0.uuid }

        var removedItems = false
        collection.animator().performBatchUpdates({

            let oldUUIDs = Model.sharedFilter.filteredDrops.map { $0.uuid }
            Model.sharedFilter.updateFilter(signalUpdate: false)
            let newUUIDs = Model.sharedFilter.filteredDrops.map { $0.uuid }

            Set(oldUUIDs).union(newUUIDs).forEach { p in
                let oldIndex = oldUUIDs.firstIndex(of: p)
                let newIndex = newUUIDs.firstIndex(of: p)
                
                if let oldIndex = oldIndex, let newIndex = newIndex {
                    if oldIndex == newIndex, savedUUIDs.contains(p) { // update
                        let n = IndexPath(item: newIndex, section: 0)
                        collection.reloadItems(at: [n])
                    } else { // move
                        let i1 = IndexPath(item: oldIndex, section: 0)
                        let i2 = IndexPath(item: newIndex, section: 0)
                        collection.moveItem(at: i1, to: i2)
                    }
                } else if let newIndex = newIndex { // insert
                    let n = IndexPath(item: newIndex, section: 0)
                    collection.insertItems(at: [n])
                } else if let oldIndex = oldIndex { // remove
                    let o = IndexPath(item: oldIndex, section: 0)
                    collection.deleteItems(at: [o])
                    removedItems = true
                }
            }
        })
        if removedItems {
            self.itemsDeleted()
        }
                
        var index = 0
        var indexSet = Set<IndexPath>()
        for i in Model.sharedFilter.filteredDrops {
            if selectedUUIDS.contains(i.uuid) {
                indexSet.insert(IndexPath(item: index, section: 0))
            }
            index += 1
        }
        if !indexSet.isEmpty {
            collection.selectItems(at: indexSet, scrollPosition: [.centeredHorizontally, .centeredVertically])
        }

        touchBarScrubber?.reloadData()
        
        updateTitle()
    }
    
    private func itemsDeleted() {
        if Model.sharedFilter.filteredDrops.isEmpty {
            
            if Model.sharedFilter.isFiltering {
                resetSearch(andLabels: true)
            }
            updateEmptyView()
            blurb(Greetings.randomCleanLine)
        }
    }

    @objc func removeLock(_ sender: Any?) {
        let items = removableLockSelectedItems
        let plural = items.count > 1
        let label = "Remove Lock" + (plural ? "s" : "")
        
        LocalAuth.attempt(label: label) { [weak self] success in
            if success {
                for item in items {
                    item.lockPassword = nil
                    item.lockHint = nil
                    item.needsUnlock = false
                    item.markUpdated()
                }
            } else {
                self?.removeLockWithPassword(items: items, label: label, plural: plural)
            }
        }
    }
    
    private func removeLockWithPassword(items: [ArchivedItem], label: String, plural: Bool) {
		let a = NSAlert()
		a.messageText = label
		a.informativeText = plural ? "Please enter the password you provided when locking these items." : "Please enter the password you provided when locking this item."
		a.addButton(withTitle: label)
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
					successCount += 1
				}
				if successCount == 0 {
                    self?.removeLockWithPassword(items: items, label: label, plural: plural)
				} else {
					Model.save()
				}
			}
		}
	}

	func addCellToSelection(_ sender: DropCell) {
		if let cellItem = sender.representedObject as? ArchivedItem, let index = Model.sharedFilter.filteredDrops.firstIndex(of: cellItem) {
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
        let label = "Access Locked Item" + (plural ? "s" : "")

        LocalAuth.attempt(label: label) { [weak self] success in
            if success {
                for item in items {
                    item.needsUnlock = false
                    item.postModified()
                }
            } else {
                self?.unlockWithPassword(items: items, label: label, plural: plural)
            }
        }
    }

    private func unlockWithPassword(items: [ArchivedItem], label: String, plural: Bool) {
		let a = NSAlert()
        a.messageText = label
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
					self?.unlockWithPassword(items: items, label: label, plural: plural)
				}
			}
		}
	}

	@objc func info(_ sender: Any?) {
		for item in collection.actionableSelectedItems {
			if NSApp.currentEvent?.modifierFlags.contains(.option) ?? false {
				item.tryOpen(from: self)
			} else {
				let uuid = item.uuid
				if DetailController.showingUUIDs.contains(uuid) {
					NotificationCenter.default.post(name: .ForegroundDisplayedItem, object: uuid)
				} else {
					performSegue(withIdentifier: NSStoryboardSegue.Identifier("showDetail"), sender: item)
				}
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
		for item in collection.actionableSelectedItems {
			item.tryOpen(from: self)
		}
	}

	@objc func copy(_ sender: Any?) {
		let g = NSPasteboard.general
		g.clearContents()
		for item in collection.actionableSelectedItems {
			if let pi = item.pasteboardItem(forDrag: false) {
				g.writeObjects([pi])
			}
		}
	}

	@objc func duplicateItem(_ sender: Any?) {
		for item in collection.actionableSelectedItems {
			if Model.drops.contains(item) { // sanity check
				Model.duplicate(item: item)
			}
		}
	}

	@objc func moveToTop(_ sender: Any?) {
        Model.sendToTop(items: collection.actionableSelectedItems)
	}

	@objc func delete(_ sender: Any?) {
		let items = collection.actionableSelectedItems
		if items.isEmpty { return }
		if PersistedOptions.unconfirmedDeletes {
            Model.delete(items: items)
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
                    Model.delete(items: items)
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

	var lockableSelectedItems: [ArchivedItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = Model.sharedFilter.filteredDrops[$0.item]
			let isLocked = item.isLocked
			let canBeLocked = !isLocked || (isLocked && !item.needsUnlock)
			return (!canBeLocked || item.isImportedShare) ? nil : item
		}
	}

	var selectedItems: [ArchivedItem] {
		return collection.selectionIndexPaths.map {
			Model.sharedFilter.filteredDrops[$0.item]
		}
	}

	var removableLockSelectedItems: [ArchivedItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = Model.sharedFilter.filteredDrops[$0.item]
			return (!item.isLocked || item.isImportedShare) ? nil : item
		}
	}

	var unlockableSelectedItems: [ArchivedItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = Model.sharedFilter.filteredDrops[$0.item]
			return (!item.needsUnlock || item.isImportedShare) ? nil : item
		}
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(copy(_:)), #selector(shareSelected(_:)), #selector(moveToTop(_:)), #selector(info(_:)), #selector(open(_:)), #selector(delete(_:)), #selector(editLabels(_:)), #selector(duplicateItem(_:)):
			return !collection.actionableSelectedItems.isEmpty

		case #selector(editNotes(_:)):
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

	@objc func editNotes(_ sender: Any?) {
		performSegue(withIdentifier: "editNotes", sender: nil)
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
			if let item = sender as? ArchivedItem,
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

		case "editNotes":
			if let destination = segue.destinationController as? NotesEditor {
				destination.uuids = collection.actionableSelectedItems.map { $0.uuid }
			}

		case "showProgress":
			progressController = segue.destinationController as? ProgressViewController

		default: break
		}
	}

	private func updateEmptyView() {
		if Model.drops.isEmpty && emptyView.alphaValue < 1 {
			emptyView.animator().alphaValue = 1

		} else if emptyView.alphaValue > 0, !Model.drops.isEmpty {
			emptyView.animator().alphaValue = 0
			emptyLabel.animator().alphaValue = 0
		}
	}

	private func blurb(_ text: String) {
		emptyLabel.alphaValue = 0
		emptyLabel.stringValue = text
		emptyLabel.animator().alphaValue = 1
		DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
			self?.emptyLabel.animator().alphaValue = 0
		}
	}

	//////////////////////////////////////////////////// Quicklook

	override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
		return !collection.selectionIndexPaths.isEmpty
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
		return Model.sharedFilter.filteredDrops[index].previewableTypeItem?.quickLookItem
	}

	func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
		if event.type == .keyDown {
			collection.keyDown(with: event)
			return true
		}
		return false
	}

	func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
		guard let qlItem = item as? Component.PreviewItem else { return .zero }
		if let drop = Model.item(uuid: qlItem.parentUuid), let index = Model.sharedFilter.filteredDrops.firstIndex(of: drop) {
			let frameRealativeToCollection = collection.frameForItem(at: index)
			let frameRelativeToWindow = collection.convert(frameRealativeToCollection, to: nil)
			let frameRelativeToScreen = view.window!.convertToScreen(frameRelativeToWindow)
			return frameRelativeToScreen
		}
		return .zero
	}

	func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
		let visibleCells = collection.visibleItems()
		if let qlItem = item as? Component.PreviewItem,
			let parentUuid = Model.component(uuid: qlItem.uuid.uuidString)?.parentUuid,
			let cellIndex = visibleCells.firstIndex(where: { ($0.representedObject as? ArchivedItem)?.uuid == parentUuid }) {
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
