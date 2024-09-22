@preconcurrency import AppKit
import GladysCommon
import GladysUI
import PopTimer
@preconcurrency import QuickLookUI

final class ViewController: NSViewController, NSCollectionViewDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate,
    NSMenuItemValidation, NSSearchFieldDelegate, NSTouchBarDelegate, FilterDelegate, HighlightListener {
    let filter = Filter()

    @IBOutlet private var collection: MainCollectionView!

    @IBOutlet private var searchHolder: NSView!
    @IBOutlet private var searchBar: NSSearchField!

    @IBOutlet private var emptyView: NSImageView!
    @IBOutlet private var emptyLabel: NSTextField!

    @IBOutlet private var topBackground: NSVisualEffectView!
    @IBOutlet private var titleBarBackground: NSView!

    @IBOutlet private var translucentView: NSVisualEffectView!

    private var highlightRegistration: HighlightRequest.Registration?
    private var modeChangeRegistration: NSObjectProtocol?

    override func viewWillAppear() {
        handleLayout()
        Task {
            await updateTitle()
        }
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

    func reloadItems() {
        presentationInfoCache.reset()
        collection.reloadData()
    }

    func modelFilterContextChanged(_: Filter, animate _: Bool) {
        itemCollectionNeedsDisplay()
        updateEmptyView()
    }

    private lazy var dataSource = NSCollectionViewDiffableDataSource<SectionIdentifier, ItemIdentifier>(collectionView: collection) { _, _, archivedItem in
        let item = DropCell()
        item.representedObject = DropStore.item(uuid: archivedItem.uuid)
        return item
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            collection.dataSource = dataSource
            collection.registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.item.identifier), NSPasteboard.PasteboardType(UTType.content.identifier)])
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        filter.delegate = self
        showSearch = false

        updateDragOperationIndicators()

        notifications(for: .ModelDataUpdated) { [weak self] object in
            guard let self else { return }
            filter.rebuildLabels()
            updateEmptyView()
            modelDataUpdate(object)
        }

        notifications(for: .ItemCollectionNeedsDisplay) { [weak self] _ in
            self?.itemCollectionNeedsDisplay()
        }

        notifications(for: .CloudManagerStatusChanged) { [weak self] _ in
            await self?.updateTitle()
        }

        notifications(for: .LabelSelectionChanged) { [weak self] _ in
            guard let self else { return }
            collection.deselectAll(nil)
            filter.update(signalUpdate: .animated)
            await updateTitle()
        }

        notifications(for: .AlwaysOnTopChanged) { [weak self] _ in
            self?.updateAlwaysOnTop()
        }

        notifications(for: NSScroller.preferredScrollerStyleDidChangeNotification) { [weak self] _ in
            self?.handleLayout()
        }

        // Not using notifications macro because registration needs to be immediate
        highlightRegistration = HighlightRequest.registerListener(listener: self)

        modeChangeRegistration = collection.observe(\.effectiveAppearance) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                self.reloadItems()
            }
        }

        notifications(for: .ItemsAddedBySync) { [weak self] _ in
            self?.filter.update(signalUpdate: .animated)
        }

        Task {
            await updateTitle()
        }

        updateDataSource(animated: false)
        updateEmptyView()

        setupMouseMonitoring()
    }

    deinit {
        modeChangeRegistration = nil
        highlightRegistration?.cancel()
        log("Main VC deinitialised")
    }

    private func itemCollectionNeedsDisplay() {
        updateDataSource(animated: true)
        touchBarScrubber?.reloadData()
        Task {
            await updateTitle()
        }
    }

    private func updateDataSource(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<SectionIdentifier, ItemIdentifier>()
        let section = SectionIdentifier(label: nil)
        snapshot.appendSections([section])
        let identifiers = filter.filteredDrops.map { ItemIdentifier(label: nil, uuid: $0.uuid) }
        snapshot.appendItems(identifiers)
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private var optionPressed: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
    }

    private func updateTitle() async {
        guard let window = view.window else { return }

        let title: String = if filter.isFilteringLabels {
            filter.enabledLabelsForTitles.joined(separator: ", ")
        } else {
            "Gladys"
        }

        let items = collection.actionableSelectedItems

        if let syncStatus = await CloudManager.syncProgressString {
            window.title = "\(title) — \(syncStatus)"

        } else if items.count > 1 {
            let selectedItems = items.map(\.uuid)
            window.title = "…"
            Task {
                let size = await DropStore.sizeForItems(uuids: selectedItems)
                let sizeString = diskSizeFormatter.string(fromByteCount: size)
                let selectedReport = "Selected \(selectedItems.count) Items: \(sizeString)"
                window.title = "\(title) — \(selectedReport)"
            }
        } else {
            window.title = title
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

    @objc private func toggleTitlebar(_: Any?) {
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

    func collectionView(_: NSCollectionView, didSelectItemsAt _: Set<IndexPath>) {
        if collection.selectionIndexPaths.isPopulated, QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
        Task {
            await updateTitle()
        }
    }

    func collectionView(_: NSCollectionView, didDeselectItemsAt _: Set<IndexPath>) {
        Task {
            await updateTitle()
        }
    }

    override func viewWillLayout() {
        super.viewWillLayout()
        handleLayout()
    }

    private func handleLayout() {
        guard let window = view.window else { return }

        let scrollbarInset: CGFloat = if let v = collection.enclosingScrollView?.verticalScroller, v.scrollerStyle == .legacy {
            v.frame.width
        } else {
            0
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

    @objc func shareSelected(_: Any?) {
        guard let itemToShare = collection.actionableSelectedItems.first,
              let i = filter.filteredDrops.firstIndex(of: itemToShare),
              let cell = collection.item(at: IndexPath(item: i, section: 0))
        else { return }

        collection.deselectAll(nil)
        collection.selectItems(at: [IndexPath(item: i, section: 0)], scrollPosition: [])
        let p = NSSharingServicePicker(items: [itemToShare.itemProviderForSharing])
        let f = cell.view.frame
        let centerFrame = NSRect(origin: CGPoint(x: f.midX - 1, y: f.midY - 1), size: CGSize(width: 2, height: 2))
        Task {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            p.show(relativeTo: centerFrame, of: self.collection, preferredEdge: .minY)
        }
    }

    @IBAction private func searchDoneSelected(_: NSButton) {
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

    @IBAction func findSelected(_: NSMenuItem?) {
        if showSearch {
            resetSearch(andLabels: false)
            Task {
                view.window?.makeFirstResponder(self.collection)
            }
        } else {
            showSearch = true
            Task {
                view.window?.makeFirstResponder(self.searchBar)
            }
        }
    }

    private lazy var searchPopTimer = PopTimer(timeInterval: 0.2) { [weak self] in
        guard let self else { return }
        let str = searchBar.stringValue
        filter.text = str.isEmpty ? nil : str
        updateEmptyView()
    }

    func controlTextDidChange(_: Notification) {
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

    func highlightItem(request: HighlightRequest) async {
        // focusOnChild ignored for now
        resetSearch(andLabels: true)
        if let i = DropStore.indexOfItem(with: request.uuid) {
            let ip = IndexPath(item: i, section: 0)
            collection.scrollToItems(at: [ip], scrollPosition: .centeredVertically)
            collection.selectionIndexes = IndexSet(integer: i)
            switch request.extraAction {
            case .open:
                if let item = DropStore.item(uuid: request.uuid) {
                    item.tryOpen(from: self)
                }
            case .detail:
                info(nil)
            case .preview:
                let previewVisible = previewPanel?.isVisible ?? false
                if !previewVisible {
                    toggleQuickLookPreviewPanel(self)
                }
            case .none, .userDefault:
                break
            }
        }
    }

    private var showSearch = false {
        didSet {
            searchHolder.isHidden = !showSearch
            updateScrollviewInsets()
        }
    }

    private func updateScrollviewInsets() {
        Task {
            guard let scrollView = self.collection.enclosingScrollView else { return }
            let offset = scrollView.contentView.bounds.origin.y
            let topHeight = self.topBackground.frame.size.height
            scrollView.contentInsets = NSEdgeInsets(top: topHeight, left: 0, bottom: 0, right: 0)
            if offset <= 0 {
                Task {
                    try? await Task.sleep(nanoseconds: 10 * NSEC_PER_MSEC)
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

    func collectionView(_: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        filter.filteredDrops[indexPath.item].pasteboardItem(forDrag: true)
    }

    func collectionView(_: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with _: NSEvent) -> Bool {
        !indexPaths.contains { filter.filteredDrops[$0.item].flags.contains(.needsUnlock) }
    }

    func collectionView(_: NSCollectionView, validateDrop _: NSDraggingInfo, proposedIndexPath _: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        proposedDropOperation.pointee = .on
        return draggingIndexPaths == nil ? .copy : .move
    }

    func collectionView(_: NSCollectionView, draggingSession _: NSDraggingSession, willBeginAt _: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        updateDragOperationIndicators()
        draggingIndexPaths = Array(indexPaths)
    }

    private var draggingIndexPaths: [IndexPath]?

    func collectionView(_: NSCollectionView, draggingSession session: NSDraggingSession, endedAt _: NSPoint, dragOperation _: NSDragOperation) {
        if let d = draggingIndexPaths, d.isPopulated {
            if optionPressed {
                let items = d.map { filter.filteredDrops[$0.item] }
                Model.delete(items: items)
            }
            draggingIndexPaths = nil
        }
        session.draggingPasteboard.clearContents() // release promise providers
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation _: NSCollectionView.DropOperation) -> Bool {
        if let s = draggingInfo.draggingSource as? NSCollectionView, s == collectionView, let dip = draggingIndexPaths {
            draggingIndexPaths = nil // protect from internal alt-move
            if let firstDip = dip.first, firstDip == indexPath {
                return false
            }

            var destinationIndex = filter.nearestUnfilteredIndexForFilteredIndex(indexPath.item, checkForWeirdness: false)
            let count = DropStore.allDrops.count
            if destinationIndex >= count {
                destinationIndex = count - 1
            }

            var indexPath = indexPath
            if indexPath.item >= filter.filteredDrops.count {
                indexPath.item = filter.filteredDrops.count - 1
            }

            for draggingIndexPath in dip.sorted(by: { $0.item > $1.item }) {
                let sourceItem = filter.filteredDrops[draggingIndexPath.item]
                let sourceIndex = DropStore.indexOfItem(with: sourceItem.uuid)!
                DropStore.removeDrop(at: sourceIndex)
                DropStore.insert(drop: sourceItem, at: destinationIndex)
                collection.deselectAll(nil)
            }
            Task {
                await Model.save()
            }
            return true
        } else {
            let p = draggingInfo.draggingPasteboard
            let result = Model.addItems(from: p, at: indexPath, overrides: nil, filterContext: filter)
            switch result {
            case .success:
                return true
            case .noData:
                return false
            }
        }
    }

    private func modelDataUpdate(_ object: Any?) {
        let oldUUIDs = filter.filteredDrops.map(\.uuid)
        let oldSet = Set(oldUUIDs)

        let previous = filter.enabledToggles
        filter.rebuildLabels()
        let forceAnnounce = previous != filter.enabledToggles
        filter.update(signalUpdate: .animated, forceAnnounce: forceAnnounce)

        let parameters = object as? [AnyHashable: Any]
        if let uuidsToReload = (parameters?["updated"] as? Set<UUID>)?.intersection(oldSet), uuidsToReload.isPopulated {
            DropStore.reloadCells(for: uuidsToReload)
        }

        let newUUIDs = filter.filteredDrops.map(\.uuid)
        let newSet = Set(newUUIDs)

        let removed = oldSet.subtracting(newSet)
        let added = newSet.subtracting(oldSet)

        let removedItems = removed.isPopulated
        let ipsInsered = added.isPopulated
        let ipsMoved = !removedItems && !ipsInsered && oldUUIDs != newUUIDs

        if removedItems || ipsInsered || ipsMoved {
            if removedItems {
                itemsDeleted()
            }
        }

        touchBarScrubber?.reloadData()

        Task {
            await updateTitle()
        }
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

    @objc func removeLock(_: Any?) {
        let items = removableLockSelectedItems
        let plural = items.count > 1
        let label = "Remove Lock" + (plural ? "s" : "")

        Task {
            guard let success = await LocalAuth.attempt(label: label) else {
                return
            }
            if success {
                for item in items {
                    item.lockPassword = nil
                    item.lockHint = nil
                    item.flags.remove(.needsUnlock)
                    item.markUpdated()
                }
            } else {
                removeLockWithPassword(items: items, label: label, plural: plural)
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
                Task {
                    await Model.save()
                }
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
            if text.isPopulated {
                let hashed = sha1(text)
                for item in items {
                    item.flags.insert(.needsUnlock)
                    item.lockPassword = hashed
                    item.lockHint = hint.stringValue.isEmpty ? nil : hint.stringValue
                    item.markUpdated()
                }
                Task {
                    await Model.save()
                }
            } else {
                createLock(sender)
            }
        }
    }

    @objc func unlock(_: Any?) {
        let items = unlockableSelectedItems
        let plural = items.count > 1
        let label = "Access Locked Item" + (plural ? "s" : "")

        Task {
            guard let success = await LocalAuth.attempt(label: label) else {
                return
            }

            if success {
                for item in items {
                    item.flags.remove(.needsUnlock)
                    item.postModified()
                }
            } else {
                unlockWithPassword(items: items, label: label, plural: plural)
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

    @objc func info(_: Any?) {
        for item in collection.actionableSelectedItems {
            if NSApp.currentEvent?.modifierFlags.contains(.option) ?? false {
                item.tryOpen(from: self)
            } else {
                let uuid = item.uuid
                if DetailController.showingUUIDs.contains(uuid) {
                    sendNotification(name: .ForegroundDisplayedItem, object: uuid)
                } else {
                    performSegue(withIdentifier: NSStoryboardSegue.Identifier("showDetail"), sender: item)
                }
            }
        }
    }

    private var labelController: LabelSelectionViewController?
    @objc private func showLabels(_: Any?) {
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

    @objc func editLabels(_: Any?) {
        performSegue(withIdentifier: NSStoryboardSegue.Identifier("editLabels"), sender: nil)
    }

    @objc func open(_: Any?) {
        for item in collection.actionableSelectedItems {
            item.tryOpen(from: self)
        }
    }

    @objc func copy(_: Any?) {
        let g = NSPasteboard.general
        g.clearContents()
        for item in collection.actionableSelectedItems {
            if let pi = item.pasteboardItem(forDrag: false) {
                g.writeObjects([pi])
            }
        }
    }

    @objc func duplicateItem(_: Any?) {
        for item in collection.actionableSelectedItems where DropStore.contains(uuid: item.uuid) {
            Model.duplicate(item: item)
        }
    }

    @objc func moveToTop(_: Any?) {
        Model.sendToTop(items: collection.actionableSelectedItems)
    }

    func updateColour(_ sender: NSMenuItem) {
        let color = ItemColor.allCases[sender.tag]
        var changed = false
        for item in collection.actionableSelectedItems where DropStore.contains(uuid: item.uuid) {
            item.highlightColor = color
            item.markUpdated()
            changed = true
        }
        if changed {
            Task {
                await Model.save()
            }
        }
    }

    @objc func delete(_: Any?) {
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

    @objc private func paste(_: Any?) {
        _ = Model.addItems(from: NSPasteboard.general, at: IndexPath(item: 0, section: 0), overrides: nil, filterContext: filter)
    }

    var lockableSelectedItems: [ArchivedItem] {
        collection.selectionIndexPaths.compactMap {
            let item = filter.filteredDrops[$0.item]
            let isLocked = item.isLocked
            let canBeLocked = !isLocked || (isLocked && !item.flags.contains(.needsUnlock))
            return (!canBeLocked || item.isImportedShare) ? nil : item
        }
    }

    var selectedItems: [ArchivedItem] {
        collection.selectionIndexPaths.map {
            filter.filteredDrops[$0.item]
        }
    }

    var removableLockSelectedItems: [ArchivedItem] {
        collection.selectionIndexPaths.compactMap {
            let item = filter.filteredDrops[$0.item]
            return (!item.isLocked || item.isImportedShare) ? nil : item
        }
    }

    var unlockableSelectedItems: [ArchivedItem] {
        collection.selectionIndexPaths.compactMap {
            let item = filter.filteredDrops[$0.item]
            return (!item.flags.contains(.needsUnlock) || item.isImportedShare) ? nil : item
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)), #selector(delete(_:)), #selector(duplicateItem(_:)), #selector(editLabels(_:)), #selector(info(_:)), #selector(moveToTop(_:)), #selector(open(_:)), #selector(shareSelected(_:)):
            return collection.actionableSelectedItems.isPopulated

        case #selector(editNotes(_:)):
            return collection.actionableSelectedItems.isPopulated

        case #selector(paste(_:)):
            return NSPasteboard.general.pasteboardItems?.count ?? 0 > 0

        case #selector(unlock(_:)):
            return unlockableSelectedItems.isPopulated

        case #selector(removeLock(_:)):
            return removableLockSelectedItems.isPopulated

        case #selector(createLock(_:)):
            return lockableSelectedItems.isPopulated

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

    @objc private func editNotes(_: Any?) {
        performSegue(withIdentifier: "editNotes", sender: nil)
    }

    @objc func toggleQuickLookPreviewPanel(_: Any?) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
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
                destination.selectedItems = collection.actionableSelectedItems.map(\.uuid)
            }

        case "editNotes":
            if let destination = segue.destinationController as? NotesEditor {
                destination.uuids = collection.actionableSelectedItems.map(\.uuid)
            }

        default: break
        }
    }

    func restoreState(from windowState: WindowController.State, forceVisibleNow: Bool = false) {
        if windowState.labels.isPopulated {
            filter.enableLabelsByName(Set(windowState.labels))
            filter.update(signalUpdate: .instant)
        }
        if let text = windowState.search, text.isPopulated {
            startSearch(initialText: text)
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
        let empty = DropStore.allDrops.isEmpty

        if empty, emptyView.alphaValue < 1 {
            emptyView.animator().alphaValue = 1

        } else if emptyView.alphaValue > 0, !empty {
            emptyView.animator().alphaValue = 0
            emptyLabel.animator().alphaValue = 0
        }
    }

    private func blurb(_ text: String) {
        emptyLabel.alphaValue = 0
        emptyLabel.stringValue = text
        emptyLabel.animator().alphaValue = 1
        Task {
            try? await Task.sleep(nanoseconds: 6000 * NSEC_PER_MSEC)
            emptyLabel.animator().alphaValue = 0
        }
    }

    //////////////////////////////////////////////////// Quicklook

    override func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated {
            collection.selectionIndexPaths.isPopulated
        }
    }

    private var previewPanel: QLPreviewPanel?
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            previewPanel = panel
            panel.delegate = self
            panel.dataSource = self
        }
    }

    override func endPreviewPanelControl(_: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            previewPanel = nil
        }
    }

    nonisolated func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            collection.selectionIndexPaths.count
        }
    }

    nonisolated func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated {
            let index = collection.selectionIndexPaths.sorted()[index].item
            return filter.filteredDrops[index].previewableTypeItem?.quickLookItem
        }
    }

    nonisolated func previewPanel(_: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown {
            MainActor.assumeIsolated {
                collection.keyDown(with: event)
            }
            return true
        }
        return false
    }

    nonisolated func previewPanel(_: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        guard let qlItem = item as? Component.PreviewItem else { return .zero }
        return MainActor.assumeIsolated {
            if let drop = DropStore.item(uuid: qlItem.parentUuid), let index = filter.filteredDrops.firstIndex(of: drop) {
                let frameRealativeToCollection = collection.frameForItem(at: index)
                let frameRelativeToWindow = collection.convert(frameRealativeToCollection, to: nil)
                let frameRelativeToScreen = view.window!.convertToScreen(frameRelativeToWindow)
                return frameRelativeToScreen
            }
            return .zero
        }
    }

    nonisolated func previewPanel(_: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect _: UnsafeMutablePointer<NSRect>!) -> Any! {
        guard let qlItem = item as? Component.PreviewItem else {
            return nil
        }

        let visibleCells = MainActor.assumeIsolated { collection.visibleItems() }

        guard let cellIndex = visibleCells.firstIndex(where: { cell in
            MainActor.assumeIsolated {
                let o = cell.representedObject as? ArchivedItem
                return o?.uuid == qlItem.parentUuid
            }
        }) else {
            return nil
        }

        let cell = visibleCells[cellIndex] as? DropCell
        return MainActor.assumeIsolated { cell?.previewImage }
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
            guard let self else { return }
            handleMouseReleased()
        }

        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.handleMouseMoved(draggingData: false)
            return e
        }

        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self else { return }
            handleMouseMoved(draggingData: false)
        }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self else { return }
            handleMouseMoved(draggingData: dragPboardChangeCount != dragPboard.changeCount)
        }
    }

    private func handleMouseMoved(draggingData: Bool) {
        let checkingDrag = PersistedOptions.autoShowWhenDragging && draggingData
        let autoShowOnEdge = PersistedOptions.autoShowFromEdge
        guard checkingDrag || autoShowOnEdge > 0, let window = view.window else { return }

        let mouseLocation = NSEvent.mouseLocation
        if !checkingDrag, window.isVisible {
            if autoShown, autoShowOnEdge > 0, window.frame.insetBy(dx: -30, dy: -30).contains(mouseLocation) {
                enteredWindowAfterAutoShow = true
                hideTimer?.invalidate()
                hideTimer = nil

            } else if enteredWindowAfterAutoShow, presentedViewControllers?.isEmpty ?? true {
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
        if autoShown, wasDraggingData, !window.frame.contains(mouseLocation) {
            hideWindowBecauseOfMouse(window: window)
        }
    }

    private weak var hideTimer: Timer?

    func showWindow(window: NSWindow, startHideTimerIfNeeded: Bool = false) {
        hideTimer?.invalidate()
        hideTimer = nil
        enteredWindowAfterAutoShow = false
        autoShown = startHideTimerIfNeeded

        window.collectionBehavior = [.moveToActiveSpace, .canJoinAllApplications]
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()
        window.animator().alphaValue = 1

        if startHideTimerIfNeeded {
            let time = TimeInterval(PersistedOptions.autoHideAfter)
            if time > 0 {
                hideTimer = Timer.scheduledTimer(withTimeInterval: time, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.hideWindowBecauseOfMouse(window: window)
                    }
                }
            }
        }
    }

    func hideWindowBecauseOfMouse(window: NSWindow) {
        enteredWindowAfterAutoShow = false
        autoShown = false
        hideTimer?.invalidate()
        hideTimer = nil

        NSAnimationContext.runAnimationGroup { _ in
            window.animator().alphaValue = 0
        }
        completionHandler: {
            window.orderOut(nil)
        }
    }
}
