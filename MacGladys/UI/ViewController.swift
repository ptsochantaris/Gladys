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
import DeepDiff

final class ViewController: NSViewController, NSCollectionViewDelegate, NSCollectionViewDataSource, QLPreviewPanelDataSource, QLPreviewPanelDelegate,
                            NSMenuItemValidation, NSSearchFieldDelegate, NSTouchBarDelegate, FilterDelegate {

    let filter = Filter()

	@IBOutlet private var collection: MainCollectionView!

	private static let dropCellId = NSUserInterfaceItemIdentifier("DropCell")

	@IBOutlet private var searchHolder: NSView!
	@IBOutlet private var searchBar: NSSearchField!

	@IBOutlet private var emptyView: NSImageView!
	@IBOutlet private var emptyLabel: NSTextField!

	@IBOutlet private var topBackground: NSVisualEffectView!
	@IBOutlet private var titleBarBackground: NSView!

	@IBOutlet private var translucentView: NSVisualEffectView!

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
    
    func modelFilterContextChanged(_ modelFilterContext: Filter, animate: Bool) {
        itemCollectionNeedsDisplay()
    }

	private var observers = [NSObjectProtocol]()

	override func viewDidLoad() {
		super.viewDidLoad()

        filter.delegate = self
		showSearch = false

		collection.registerForDraggedTypes([NSPasteboard.PasteboardType(kUTTypeItem as String), NSPasteboard.PasteboardType(kUTTypeContent as String)])
		updateDragOperationIndicators()

		let n = NotificationCenter.default

		let a1 = n.addObserver(forName: .ModelDataUpdated, object: nil, queue: .main) { [weak self] notification in
            self?.filter.rebuildLabels()
            self?.updateEmptyView()
            self?.modelDataUpdate(notification)
		}

		let a3 = n.addObserver(forName: .ItemCollectionNeedsDisplay, object: nil, queue: .main) { [weak self] _ in
            self?.itemCollectionNeedsDisplay()
		}

		let a4 = n.addObserver(forName: .CloudManagerStatusChanged, object: nil, queue: .main) { [weak self] _ in
			self?.updateTitle()
		}

		let a5 = n.addObserver(forName: .LabelSelectionChanged, object: nil, queue: .main) { [weak self] _ in
			self?.collection.deselectAll(nil)
            self?.filter.updateFilter(signalUpdate: .animated)
			self?.updateTitle()
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
        
        let a13 = n.addObserver(forName: .ItemAddedBySync, object: nil, queue: .main) { [weak self] _ in
            self?.filter.updateFilter(signalUpdate: .animated)
        }
        
		observers = [a1, a3, a4, a5, a8, a9, a11, a12, a13]

        updateTitle()
        updateEmptyView()
        setupMouseMonitoring()
	}
    
    private func itemCollectionNeedsDisplay() {
        collection.animator().reloadData()
        touchBarScrubber?.reloadData()
        DispatchQueue.main.async {
            self.updateTitle()
        }
    }
    
	private var optionPressed: Bool {
		return NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
	}

	private func updateTitle() {
		var title: String
		if filter.isFilteringLabels {
			title = filter.enabledLabelsForTitles.joined(separator: ", ")
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
		if filter.filteredDrops.isEmpty {
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
		return filter.filteredDrops.count
	}

	func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
		let i = collectionView.makeItem(withIdentifier: ViewController.dropCellId, for: indexPath)
		i.representedObject = filter.filteredDrops[indexPath.item]
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
        observers.forEach {
			NotificationCenter.default.removeObserver($0)
		}
	}

	@objc func shareSelected(_ sender: Any?) {
		guard let itemToShare = collection.actionableSelectedItems.first,
			let i = filter.filteredDrops.firstIndex(of: itemToShare),
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
        searchPopTimer.push()

		if andLabels {
			filter.disableAllLabels()
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

    private lazy var searchPopTimer = {
        return PopTimer(timeInterval: 0.2) { [weak self] in
            guard let s = self else { return }
            let str = s.searchBar.stringValue
            s.filter.text = str.isEmpty ? nil : str
            s.updateEmptyView()
        }
    }()
    
	func controlTextDidChange(_ obj: Notification) {
        collection.selectionIndexes = []
        searchPopTimer.push()
	}

    func touchedItem(_ item: ArchivedItem) {
        if let index = filter.filteredDrops.firstIndex(of: item) {
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
        if let i = Model.firstIndexOfItem(with: request.uuid) {
            let ip = IndexPath(item: i, section: 0)
            collection.scrollToItems(at: [ip], scrollPosition: .centeredVertically)
            collection.selectionIndexes = IndexSet(integer: i)
            if request.open {
                info(nil)
            } else if request.preview {
                if !(previewPanel?.isVisible ?? false) {
                    toggleQuickLookPreviewPanel(self)
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
        searchPopTimer.push()
	}

	func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
		return filter.filteredDrops[indexPath.item].pasteboardItem(forDrag: true)
	}

	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        return !indexPaths.contains { filter.filteredDrops[$0.item].flags.contains(.needsUnlock) }
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
				let items = d.map { filter.filteredDrops[$0.item] }
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

			var destinationIndex = filter.nearestUnfilteredIndexForFilteredIndex(indexPath.item, checkForWeirdness: false)
            let count = Model.drops.count
			if destinationIndex >= count {
				destinationIndex = count - 1
			}

			var indexPath = indexPath
			if indexPath.item >= filter.filteredDrops.count {
				indexPath.item = filter.filteredDrops.count - 1
			}

			for draggingIndexPath in dip.sorted(by: { $0.item > $1.item }) {
				let sourceItem = filter.filteredDrops[draggingIndexPath.item]
                let sourceIndex = Model.firstIndexOfItem(with: sourceItem.uuid)!
				Model.drops.remove(at: sourceIndex)
				Model.drops.insert(sourceItem, at: destinationIndex)
				collection.deselectAll(nil)
			}
			Model.save()
			return true
		} else {
			let p = draggingInfo.draggingPasteboard
            return Model.addItems(from: p, at: indexPath, overrides: nil, filterContext: filter)
		}
	}

    private func modelDataUpdate(_ notification: Notification) {
        let parameters = notification.object as? [AnyHashable: Any]
        let savedUUIDs = parameters?["updated"] as? Set<UUID> ?? Set<UUID>()
        let selectedUUIDS = collection.selectionIndexPaths.compactMap { collection.item(at: $0) }.compactMap { $0.representedObject as? ArchivedItem }.map { $0.uuid }

        var removedItems = false
        var ipsToReload = Set<IndexPath>()
        collection.animator().performBatchUpdates({

            let oldUUIDs = filter.filteredDrops.map { $0.uuid }
            filter.updateFilter(signalUpdate: .animated)
            if Model.drops.allSatisfy({ $0.shouldDisplayLoading }) {
                collection.reloadSections(IndexSet(integer: 0))
                return
            }
            let newUUIDs = filter.filteredDrops.map { $0.uuid }
            var ipsToRemove = Set<IndexPath>()
            var ipsToInsert = Set<IndexPath>()
            var moveList = [(IndexPath, IndexPath)]()

            let changes = diff(old: oldUUIDs, new: newUUIDs)
            for change in changes {
                switch change {
                case .delete(let deletion):
                    ipsToRemove.insert(IndexPath(item: deletion.index, section: 0))
                case .insert(let insertion):
                    ipsToInsert.insert(IndexPath(item: insertion.index, section: 0))
                case .move(let move):
                    moveList.append((IndexPath(item: move.fromIndex, section: 0), IndexPath(item: move.toIndex, section: 0)))
                case .replace(let reload):
                    ipsToReload.insert(IndexPath(item: reload.index, section: 0))
                }
            }
            
            for uuid in savedUUIDs {
                if let i = newUUIDs.firstIndex(of: uuid) {
                    let ip = IndexPath(item: i, section: 0)
                    ipsToReload.insert(ip)
                }
            }
            
            removedItems = !ipsToRemove.isEmpty
            
            collection.deleteItems(at: ipsToRemove)
            collection.insertItems(at: ipsToInsert)
            for move in moveList {
                collection.moveItem(at: move.0, to: move.1)
            }
            
        })

        collection.reloadItems(at: ipsToReload)

        if removedItems {
            self.itemsDeleted()
        }
                
        var index = 0
        var indexSet = Set<IndexPath>()
        for i in filter.filteredDrops {
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
        if filter.filteredDrops.isEmpty {
            
            if filter.isFiltering {
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
                    item.flags.remove(.needsUnlock)
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
        let response = a.runModal()
        if response.rawValue == 1000 {
            let text = input.stringValue
            let hash = sha1(text)
            var successCount = 0
            for item in items where item.lockPassword == hash {
                item.lockPassword = nil
                item.lockHint = nil
                item.flags.remove(.needsUnlock)
                item.markUpdated()
                successCount += 1
            }
            if successCount == 0 {
                removeLockWithPassword(items: items, label: label, plural: plural)
            } else {
                Model.save()
            }
		}
	}

	func addCellToSelection(_ sender: DropCell) {
		if let cellItem = sender.representedObject as? ArchivedItem, let index = filter.filteredDrops.firstIndex(of: cellItem) {
			let newIp = IndexPath(item: index, section: 0)
			if !collection.selectionIndexPaths.contains(newIp) {
				collection.selectionIndexPaths = [newIp]
			}
		}
	}

	@objc func createLock(_ sender: Any?) {

		let instaLock = lockableSelectedItems.filter { $0.isLocked && !$0.flags.contains(.needsUnlock) }
		for item in instaLock {
            item.flags.insert(.needsUnlock)
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
		let input = NSView(frame: NSRect(x: 0, y: 0, width: 290, height: 56))
		input.addSubview(password)
		input.addSubview(hint)
		password.nextKeyView = hint
		hint.nextKeyView = password
		a.accessoryView = input
		a.window.initialFirstResponder = password
        let response = a.runModal()
        if response.rawValue == 1000 {
            let text = password.stringValue
            if !text.isEmpty {
                let hashed = sha1(text)
                for item in items {
                    item.flags.insert(.needsUnlock)
                    item.lockPassword = hashed
                    item.lockHint = hint.stringValue.isEmpty ? nil : hint.stringValue
                    item.markUpdated()
                }
                Model.save()
            } else {
                createLock(sender)
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
                    item.flags.remove(.needsUnlock)
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
        let response = a.runModal()
        if response.rawValue == 1000 {
            let text = input.stringValue
            var successCount = 0
            let hashed = sha1(text)
            for item in items where item.lockPassword == hashed {
                item.flags.remove(.needsUnlock)
                item.postModified()
                successCount += 1
            }
            if successCount == 0 {
                unlockWithPassword(items: items, label: label, plural: plural)
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
            if Model.contains(uuid: item.uuid) { // sanity check
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
            let response = a.runModal()
            if response.rawValue == 1000 {
                Model.delete(items: items)
                if let s = a.suppressionButton, s.integerValue > 0 {
                    PersistedOptions.unconfirmedDeletes = true
                }
            }
		}
	}

	@objc func paste(_ sender: Any?) {
        Model.addItems(from: NSPasteboard.general, at: IndexPath(item: 0, section: 0), overrides: nil, filterContext: filter)
	}

	var lockableSelectedItems: [ArchivedItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = filter.filteredDrops[$0.item]
			let isLocked = item.isLocked
			let canBeLocked = !isLocked || (isLocked && !item.flags.contains(.needsUnlock))
			return (!canBeLocked || item.isImportedShare) ? nil : item
		}
	}

	var selectedItems: [ArchivedItem] {
		return collection.selectionIndexPaths.map {
            filter.filteredDrops[$0.item]
		}
	}

	var removableLockSelectedItems: [ArchivedItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = filter.filteredDrops[$0.item]
			return (!item.isLocked || item.isImportedShare) ? nil : item
		}
	}

	var unlockableSelectedItems: [ArchivedItem] {
		return collection.selectionIndexPaths.compactMap {
			let item = filter.filteredDrops[$0.item]
			return (!item.flags.contains(.needsUnlock) || item.isImportedShare) ? nil : item
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
                d.associatedFilter = filter
				d.representedObject = item
			}

		case "showLabels":
			labelController = segue.destinationController as? LabelSelectionViewController

		case "editLabels":
			if let destination = segue.destinationController as? LabelEditorViewController {
                destination.associatedFilter = filter
				destination.selectedItems = collection.actionableSelectedItems.map { $0.uuid }
			}

		case "editNotes":
			if let destination = segue.destinationController as? NotesEditor {
				destination.uuids = collection.actionableSelectedItems.map { $0.uuid }
			}

		default: break
		}
	}
    
    func restoreState(from windowState: WindowController.State, forceVisibleNow: Bool = false) {
        if !windowState.labels.isEmpty {
            filter.enableLabelsByName(Set(windowState.labels))
            filter.updateFilter(signalUpdate: .instant)
        }
        if let text = windowState.search, !text.isEmpty {
            self.showSearch = true
            self.searchBar.stringValue = text
        }
        if let w = view.window {
            w.setFrame(windowState.frame, display: false, animate: false)
            if PersistedOptions.autoShowFromEdge == 0 || forceVisibleNow {
                showWindow(window: w)
            } else {
                w.orderOut(nil)
            }
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
		return filter.filteredDrops[index].previewableTypeItem?.quickLookItem
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
		if let drop = Model.item(uuid: qlItem.parentUuid), let index = filter.filteredDrops.firstIndex(of: drop) {
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
			let parentUuid = Model.component(uuid: qlItem.uuid)?.parentUuid,
			let cellIndex = visibleCells.firstIndex(where: { ($0.representedObject as? ArchivedItem)?.uuid == parentUuid }) {
			return (visibleCells[cellIndex] as? DropCell)?.previewImage
		}
		return nil
	}
    
    /////////////////////////////// Mouse monitoring
    
    private let dragPboard = NSPasteboard(name: .drag)
    private var dragPboardChangeCount = 0
    private var enteredWindowAfterAutoShow = false
    private var autoShown = false

    private func setupMouseMonitoring() {
        dragPboardChangeCount = dragPboard.changeCount
        
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] e in
            self?.handleMouseReleased()
            return e
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseReleased()
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.handleMouseMoved(draggingData: false)
            return e
        }

        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMoved(draggingData: false)
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            if let s = self {
                s.handleMouseMoved(draggingData: s.dragPboardChangeCount != s.dragPboard.changeCount)
            }
        }
    }
    
    private func handleMouseMoved(draggingData: Bool) {
        let checkingDrag = PersistedOptions.autoShowWhenDragging && draggingData
        let autoShowOnEdge = PersistedOptions.autoShowFromEdge
        guard (checkingDrag || autoShowOnEdge > 0), let window = view.window else { return }

        let mouseLocation = NSEvent.mouseLocation
        if !checkingDrag, window.isVisible {
            if autoShown && autoShowOnEdge > 0 && window.frame.insetBy(dx: -30, dy: -30).contains(mouseLocation) {
                enteredWindowAfterAutoShow = true
                hideTimer = nil

            } else if enteredWindowAfterAutoShow && (self.presentedViewControllers?.isEmpty ?? true) {
                hideWindowBecauseOfMouse(window: window)
            }
        } else if !window.isVisible {
            if checkingDrag || mouseInActivationBoundary(at: autoShowOnEdge, mouseLocation: mouseLocation) {
                showWindow(window: window, startHideTimerIfNeeded: true)
            }
        }
    }
    
    private func mouseInActivationBoundary(at autoShowOnEdge: Int, mouseLocation: CGPoint) -> Bool {
        switch autoShowOnEdge {
        case 1: // left
            if let currentScreenFrame = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouseLocation) })?.frame {
                return mouseLocation.x <= currentScreenFrame.minX
            }
        case 2: // right
            if let currentScreenFrame = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouseLocation) })?.frame {
                return mouseLocation.x >= currentScreenFrame.maxX - 1
            }
        case 3: // top
            if let currentScreenFrame = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouseLocation) })?.frame {
                return mouseLocation.y >= currentScreenFrame.maxY - 1
            }
        case 4: // bottom
            if let currentScreenFrame = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouseLocation) })?.frame {
                return mouseLocation.y <= currentScreenFrame.minY + 1
            }
        case 5: // top left
            if let currentScreenFrame = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouseLocation) })?.frame {
                return mouseLocation.x <= currentScreenFrame.minX
                    && mouseLocation.y >= currentScreenFrame.maxY - 1
            }
        case 6: // top right
            if let currentScreenFrame = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouseLocation) })?.frame {
                return mouseLocation.y >= currentScreenFrame.maxY - 1
                    && mouseLocation.x >= currentScreenFrame.maxX - 1
            }
        case 7: // bottom left
            if let currentScreenFrame = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouseLocation) })?.frame {
                return mouseLocation.y < currentScreenFrame.minY + 1
                    && mouseLocation.x <= currentScreenFrame.minX
            }
        case 8: // bottom right
            if let currentScreenFrame = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouseLocation) })?.frame {
                return mouseLocation.y <= currentScreenFrame.minY + 1
                    && mouseLocation.x >= currentScreenFrame.maxX - 1
            }
        default:
            break
        }
        return false
    }
    
    private func handleMouseReleased() {
        guard let window = view.window, PersistedOptions.autoShowWhenDragging else { return }
        let mouseLocation = NSEvent.mouseLocation
        let newCount = dragPboard.changeCount
        let wasDraggingData = dragPboardChangeCount != newCount
        dragPboardChangeCount = newCount
        if autoShown && wasDraggingData && !window.frame.contains(mouseLocation) {
            hideWindowBecauseOfMouse(window: window)
        }
    }
    
    private var hideTimer: GladysTimer?
    
    func showWindow(window: NSWindow, startHideTimerIfNeeded: Bool = false) {
        hideTimer = nil
        enteredWindowAfterAutoShow = false
        autoShown = startHideTimerIfNeeded
        
        window.collectionBehavior = .moveToActiveSpace
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()
        window.animator().alphaValue = 1
        
        if startHideTimerIfNeeded {
            let time = TimeInterval(PersistedOptions.autoHideAfter)
            if time > 0 {
                hideTimer = GladysTimer(interval: time) { [weak self] in
                    self?.hideWindowBecauseOfMouse(window: window)
                }
            }
        }
    }
    
    func hideWindowBecauseOfMouse(window: NSWindow) {
        enteredWindowAfterAutoShow = false
        autoShown = false
        hideTimer = nil

        NSAnimationContext.runAnimationGroup { _ in
            window.animator().alphaValue = 0
        }
        completionHandler: {
            window.orderOut(nil)
        }
    }
}
