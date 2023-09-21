import AppKit
import CloudKit
import Combine
import GladysAppKit
import GladysCommon
import GladysUI
import QuickLookUI

final class ComponentCollectionView: NSCollectionView {
    weak var detailController: DetailController?
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            detailController?.toggleQuickLookPreviewPanel(self)
        } else {
            super.keyDown(with: event)
        }
    }
}

protocol FocusableTextFieldDelegate: AnyObject {
    func fieldReceivedFocus(_ field: FocusableTextField)
}

final class FocusableTextField: NSTextField {
    weak var focusDelegate: FocusableTextFieldDelegate?

    override func awakeFromNib() {
        super.awakeFromNib()
        wantsLayer = true
        layer?.cornerRadius = 2.5
    }

    override func becomeFirstResponder() -> Bool {
        focusDelegate?.fieldReceivedFocus(self)
        return super.becomeFirstResponder()
    }

    override func updateLayer() {
        if isEditable {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

final class DetailController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NewLabelControllerDelegate, NSCollectionViewDelegate, NSCollectionViewDataSource, ComponentCellDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSCloudSharingServiceDelegate, FocusableTextFieldDelegate, NSMenuItemValidation {
    static var showingUUIDs = Set<UUID>()

    var associatedFilter: Filter?

    @IBOutlet private var titleField: FocusableTextField!
    @IBOutlet private var notesField: FocusableTextField!

    @IBOutlet private var labels: NSTableView!
    @IBOutlet private var labelsScrollView: NSScrollView!
    @IBOutlet private var labelAdd: NSButton!
    @IBOutlet private var labelRemove: NSButton!

    @IBOutlet private var inviteButton: NSButton!
    @IBOutlet private var openButton: NSButton!
    @IBOutlet private var infoLabel: NSTextField!
    @IBOutlet private var readOnlyLabel: NSTextField!

    @IBOutlet private var components: ComponentCollectionView!
    private let componentCellId = NSUserInterfaceItemIdentifier("ComponentCell")

    override func viewDidLoad() {
        super.viewDidLoad()
        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(checkForChanges), name: .ModelDataUpdated, object: nil)
        n.addObserver(self, selector: #selector(foreground(_:)), name: .ForegroundDisplayedItem, object: nil)
        n.addObserver(self, selector: #selector(updateAlwaysOnTop), name: .AlwaysOnTopChanged, object: nil)

        components.registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.item.identifier), NSPasteboard.PasteboardType(UTType.content.identifier)])
        components.setDraggingSourceOperationMask(.move, forLocal: true)
        components.setDraggingSourceOperationMask(.copy, forLocal: false)
        components.detailController = self

        labels.registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.text.identifier)])
        labels.setDraggingSourceOperationMask(.move, forLocal: true)
        labels.setDraggingSourceOperationMask(.copy, forLocal: false)
        labelsScrollView.layer?.cornerRadius = 2.5

        titleField.focusDelegate = self
        notesField.focusDelegate = self
    }

    private var lastUpdate = Date.distantPast
    private var lastShareMode = ArchivedItem.ShareMode.none

    @objc private func foreground(_ notification: Notification) {
        if let uuid = notification.object as? UUID, item.uuid == uuid {
            view.window?.makeKeyAndOrderFront(self)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateAlwaysOnTop()
    }

    @objc private func updateAlwaysOnTop() {
        guard let w = view.window else { return }
        if PersistedOptions.alwaysOnTop {
            w.level = .modalPanel
        } else {
            w.level = .normal
        }
    }

    @objc private func checkForChanges() {
        if DropStore.item(uuid: item.uuid) == nil {
            view.window?.close()
        } else if lastUpdate != item.updatedAt || lastShareMode != item.shareMode {
            updateInfo()
        }
    }

    deinit {
        DetailController.showingUUIDs.remove(item.uuid)
    }

    private var itemObservation: Cancellable?
    override var representedObject: Any? {
        didSet {
            itemObservation = item.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.updateInfo()
            }
        }
    }

    private var item: ArchivedItem {
        representedObject as! ArchivedItem
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateInfo()
        labels.delegate = self
        labels.dataSource = self

        userActivity = NSUserActivity(activityType: kGladysDetailViewingActivity)
        userActivity?.needsSave = true

        DetailController.showingUUIDs.insert(item.uuid)
    }

    @objc private func updateInfo() {
        Task {
            await _updateInfo()
        }
    }

    private func _updateInfo() async {
        let shareMode = item.shareMode
        let readWrite = shareMode != .elsewhereReadOnly

        view.window?.title = (item.displayText.0 ?? "Details") + (readWrite ? "" : " — Read Only")
        titleField.placeholderString = item.nonOverridenText.0 ?? "Add Title"
        titleField.stringValue = item.titleOverride
        notesField.stringValue = item.note
        notesField.placeholderString = "Note"
        labels.reloadData()
        updateLabelButtons()
        components.animator().reloadData()
        lastUpdate = item.updatedAt
        lastShareMode = item.shareMode
        infoLabel.stringValue = item.addedString

        if await CloudManager.syncSwitchedOn {
            inviteButton.isHidden = false
            inviteButton.isEnabled = true
            infoLabel.alignment = .center
        } else {
            inviteButton.isHidden = true
            inviteButton.isEnabled = false
            infoLabel.alignment = .right
        }

        switch shareMode {
        case .none:
            readOnlyLabel.isHidden = true
            inviteButton.image = #imageLiteral(resourceName: "iconUserAdd")
            inviteButton.contentTintColor = .systemGray
        case .elsewhereReadOnly:
            readOnlyLabel.isHidden = false
            inviteButton.image = #imageLiteral(resourceName: "iconUserChecked")
            inviteButton.contentTintColor = .systemGray
        case .elsewhereReadWrite:
            readOnlyLabel.isHidden = true
            inviteButton.image = #imageLiteral(resourceName: "iconUserChecked")
            inviteButton.contentTintColor = .systemGray
        case .sharing:
            readOnlyLabel.isHidden = true
            inviteButton.image = #imageLiteral(resourceName: "iconUserChecked")
            inviteButton.contentTintColor = NSColor.g_colorTint
        }

        titleField.isEditable = readWrite
        notesField.isEditable = readWrite
        labelAdd.isEnabled = readWrite
        labelRemove.isEnabled = readWrite
    }

    override func viewWillDisappear() {
        done(notesCheck: notesField.currentEditor() != nil, titleCheck: titleField.currentEditor() != nil)
        super.viewWillDisappear()
    }

    func numberOfRows(in _: NSTableView) -> Int {
        item.labels.count
    }

    func tableView(_: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let cell = tableColumn?.dataCell as? NSTextFieldCell, row < item.labels.count else {
            return nil
        }
        cell.title = item.labels[row]
        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        updateLabelButtons()
    }

    func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let p = NSPasteboardItem()
        p.setString(item.labels[row], forType: NSPasteboard.PasteboardType(UTType.text.identifier))
        return p
    }

    func tableView(_: NSTableView, validateDrop _: NSDraggingInfo, proposedRow _: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if item.shareMode == .elsewhereReadOnly { return [] }
        return (item.shareMode != .elsewhereReadOnly && dropOperation == .above) ? .move : []
    }

    func tableView(_: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation _: NSTableView.DropOperation) -> Bool {
        if item.shareMode == .elsewhereReadOnly { return false }

        let p = info.draggingPasteboard
        guard let label = p.string(forType: NSPasteboard.PasteboardType(UTType.text.identifier)) ??
            p.string(forType: NSPasteboard.PasteboardType(UTType.plainText.identifier)) ??
            p.string(forType: NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier)) else { return false }

        var newIndex = row

        if let oldIndex = item.labels.firstIndex(of: label) {
            if oldIndex < newIndex {
                newIndex -= 1
            }
            if oldIndex == newIndex {
                return true
            }
            item.labels.remove(at: oldIndex)
        }

        item.labels.insert(label, at: newIndex)
        saveItem()
        labels.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
        return true
    }

    private func updateLabelButtons() {
        removeButton.isEnabled = !labels.selectedRowIndexes.isEmpty && readOnlyLabel.isHidden
    }

    private var previousText: String?
    func fieldReceivedFocus(_ field: FocusableTextField) {
        previousText = field.stringValue
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let o = obj.object as? NSTextField else { return }
        if o == notesField {
            done(notesCheck: true)
        } else if o == titleField {
            done(titleCheck: true)
        }
    }

    @IBOutlet private var removeButton: NSButton!
    @IBAction private func removeSelected(_: NSButton) {
        if let selected = labels.selectedRowIndexes.first {
            item.labels.remove(at: selected)
            saveItem()
            labels.selectRowIndexes([], byExtendingSelection: false)
        }
    }

    private func saveItem() {
        if DropStore.item(uuid: item.uuid) == nil {
            return
        }
        item.markUpdated()
        Task {
            await Model.save()
        }
    }

    private func done(notesCheck: Bool = false, titleCheck: Bool = false) {
        var dirty = false
        if notesCheck {
            let newText = notesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if newText != previousText {
                item.note = newText
                dirty = true
            } else {
                notesField.stringValue = newText
            }
        }
        if titleCheck {
            let newText = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if newText != previousText {
                item.titleOverride = newText
                dirty = true
            } else {
                titleField.stringValue = newText
            }
        }
        if dirty {
            saveItem()
        }
    }

    override func prepare(for segue: NSStoryboardSegue, sender _: Any?) {
        if let d = segue.destinationController as? NewLabelController {
            d.associatedFilter = associatedFilter
            d.delegate = self
            d.exclude = Set(item.labels)
        }
    }

    func newLabelController(_: NewLabelController, selectedLabel label: String) {
        if !item.labels.contains(label) {
            item.labels.append(label)
            saveItem()
        }
    }

    override func updateUserActivityState(_ userActivity: NSUserActivity) {
        super.updateUserActivityState(userActivity)
        ArchivedItem.updateUserActivity(userActivity, from: item, child: nil, titled: "Info of")
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        item.components.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let i = collectionView.makeItem(withIdentifier: componentCellId, for: indexPath) as! ComponentCell
        i.delegate = self
        i.representedObject = item.components[indexPath.item]
        return i
    }

    private func copy(item: Component) {
        let p = NSPasteboard.general
        p.clearContents()
        p.writeObjects([item.pasteboardItem(forDrag: false)])
    }

    private func delete(at index: Int) {
        let component = item.components[index]
        item.components.remove(at: index)
        Task {
            await component.deleteFromStorage()
        }
        item.renumberTypeItems()
        components.animator().deleteItems(at: [IndexPath(item: index, section: 0)])
        saveItem()
    }

    func componentCell(_ componentCell: ComponentCell, wants action: ComponentCell.Action) {
        guard let i = componentCell.representedObject as? Component, let index = item.components.firstIndex(of: i) else { return }

        components.deselectAll(nil)
        components.selectItems(at: [IndexPath(item: index, section: 0)], scrollPosition: [])

        switch action {
        case .open:
            i.tryOpen(from: self)
        case .copy:
            copy(item: i)
        case .delete:
            delete(at: index)
        case .archivePage:
            archivePage(nil)
        case .archiveThumbnail:
            archiveThumbnail(nil)
        case .share:
            shareSelected(i)
        case .edit:
            editCurrent(i)
        case .reveal:
            revealCurrent(i)
        case .focus:
            break
        }
    }

    private var selectedItem: Component? {
        if let index = components.selectionIndexes.first {
            return item.components[index]
        }
        return nil
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let count = components.selectionIndexPaths.count
        if count == 0 { return false }

        switch menuItem.action {
        case #selector(archivePage(_:)), #selector(archiveThumbnail(_:)):
            return item.shareMode != .elsewhereReadOnly && components.selectionIndexPaths.filter { item.components[$0.item].isArchivable }.count == count

        case #selector(editCurrent(_:)):
            return item.shareMode != .elsewhereReadOnly && components.selectionIndexPaths.filter { item.components[$0.item].isURL }.count == count

        case #selector(delete(_:)):
            return item.shareMode != .elsewhereReadOnly

        case #selector(toggleQuickLookPreviewPanel(_:)):
            if let first = selectedItem, first.canPreview {
                menuItem.title = "Quick Look \"\(first.oneTitle.truncateWithEllipses(limit: 30))\""
                return true
            } else {
                menuItem.title = "Quick Look"
                return false
            }

        default:
            return true
        }
    }

    @objc private func copy(_: Any?) {
        if let i = selectedItem {
            copy(item: i)
        }
    }

    @objc private func open(_: Any?) {
        if let i = selectedItem {
            i.tryOpen(from: self)
        }
    }

    @objc private func delete(_: Any?) {
        if let i = components.selectionIndexes.first {
            delete(at: i)
        }
    }

    @objc private func shareSelected(_: Any?) {
        guard let i = components.selectionIndexes.first,
              let cell = components.item(at: IndexPath(item: i, section: 0)),
              let itemToShare = cell.representedObject as? Component
        else { return }

        let p = NSSharingServicePicker(items: [itemToShare.itemProviderForSharing])
        let f = cell.view.frame
        let centerFrame = NSRect(origin: CGPoint(x: f.midX - 1, y: f.midY - 1), size: CGSize(width: 2, height: 2))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            p.show(relativeTo: centerFrame, of: self.components, preferredEdge: .minY)
        }
    }

    @objc private func editCurrent(_ sender: Any?) {
        guard let typeItem = selectedItem else { return }
        guard let urlString = typeItem.encodedUrl?.absoluteString else { return }

        let a = NSAlert()
        a.messageText = "Edit URL"
        a.addButton(withTitle: "Update")
        a.addButton(withTitle: "Cancel")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 24))
        textField.placeholderString = urlString
        textField.usesSingleLineMode = true
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.stringValue = urlString
        let input = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        input.addSubview(textField)
        a.accessoryView = input
        a.window.initialFirstResponder = textField
        a.beginSheetModal(for: view.window!) { [weak self] response in
            if let self, response.rawValue == 1000 {
                if let newURL = URL(string: textField.stringValue) {
                    typeItem.replaceURL(newURL)
                    item.markUpdated()
                    item.needsReIngest = true
                    saveItem()
                } else {
                    Task { @MainActor in
                        await genericAlert(title: "This is not a valid URL", message: textField.stringValue, windowOverride: self.view.window!)
                        self.editCurrent(sender)
                    }
                }
            }
        }
    }

    @objc private func revealCurrent(_: Any?) {
        if let typeItem = selectedItem {
            NSWorkspace.shared.activateFileViewerSelecting([typeItem.bytesPath])
        }
    }

    @objc private func archivePage(_: Any?) {
        guard let i = components.selectionIndexes.first else { return }
        let component = item.components[i]
        guard let url = component.encodedUrl as URL?, let cell = components.item(at: IndexPath(item: i, section: 0)) as? ComponentCell else { return }
        Task { @MainActor in
            cell.animateArchiving = true
            do {
                let (data, typeIdentifier) = try await WebArchiver.shared.archiveFromUrl(url.absoluteString)
                let newTypeItem = Component(typeIdentifier: typeIdentifier, parentUuid: self.item.uuid, data: data, order: self.item.components.count)
                item.components.append(newTypeItem)
                saveItem()
                cell.animateArchiving = false
            } catch {
                if let w = view.window {
                    await genericAlert(title: "Archiving failed", message: error.localizedDescription, windowOverride: w)
                    cell.animateArchiving = false
                }
            }
        }
    }

    @objc private func archiveThumbnail(_: Any?) {
        guard let i = components.selectionIndexes.first else { return }
        let component = item.components[i]
        guard let url = component.encodedUrl as URL?, let cell = components.item(at: IndexPath(item: i, section: 0)) as? ComponentCell else { return }
        cell.animateArchiving = true

        Task { @MainActor in
            let res = try? await WebArchiver.shared.fetchWebPreview(for: url.absoluteString)
            if let image = res?.image, let bits = image.representations.first as? NSBitmapImageRep, let jpegData = bits.representation(using: .jpeg, properties: [.compressionFactor: 1]) {
                let newTypeItem = Component(typeIdentifier: UTType.jpeg.identifier, parentUuid: item.uuid, data: jpegData, order: item.components.count)
                item.components.append(newTypeItem)
                saveItem()
            } else {
                await genericAlert(title: "Image Download Failed", message: "The image could not be downloaded.")
            }
            cell.animateArchiving = false
        }
    }

    override func viewWillLayout() {
        super.viewWillLayout()

        let w = components.frame.size.width
        let columns = (w / 250.0).rounded(.down)
        let s = ((w - ((columns + 1) * 10)) / columns).rounded(.down)
        (components.collectionViewLayout as! NSCollectionViewFlowLayout).itemSize = NSSize(width: s, height: 89)
    }

    func collectionView(_: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        item.components[indexPath.item].pasteboardItem(forDrag: true)
    }

    func collectionView(_: NSCollectionView, canDragItemsAt _: Set<IndexPath>, with _: NSEvent) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath _: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        if item.shareMode == .elsewhereReadOnly { return [] }

        if draggingInfo.draggingSource is ComponentCollectionView {
            proposedDropOperation.pointee = .on
            return collectionView == components ? .move : .copy
        } else {
            return []
        }
    }

    func collectionView(_: NSCollectionView, draggingSession _: NSDraggingSession, willBeginAt _: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        draggingIndexPaths = Array(indexPaths)
    }

    private var draggingIndexPaths: [IndexPath]?

    func collectionView(_: NSCollectionView, draggingSession session: NSDraggingSession, endedAt _: NSPoint, dragOperation _: NSDragOperation) {
        draggingIndexPaths = nil
        session.draggingPasteboard.clearContents() // release promise providers
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation _: NSCollectionView.DropOperation) -> Bool {
        if item.shareMode == .elsewhereReadOnly { return false }

        if let s = draggingInfo.draggingSource as? ComponentCollectionView {
            let destinationIndex = indexPath.item
            if s == collectionView, let draggingIndexPath = draggingIndexPaths?.first {
                let sourceItem = item.components[draggingIndexPath.item]
                let sourceIndex = draggingIndexPath.item
                item.components.remove(at: sourceIndex)
                item.components.insert(sourceItem, at: destinationIndex)
                item.renumberTypeItems()
                components.animator().moveItem(at: draggingIndexPath, to: indexPath)
                components.deselectAll(nil)
                saveItem()
                return true

            } else if let pasteboardItem = draggingInfo.draggingPasteboard.pasteboardItems?.first, let type = pasteboardItem.types.first, let data = pasteboardItem.data(forType: type) {
                let typeItem = Component(typeIdentifier: type.rawValue, parentUuid: item.uuid, data: data, order: 99999)
                item.components.insert(typeItem, at: destinationIndex)
                item.renumberTypeItems()
                components.animator().insertItems(at: [indexPath])
                saveItem()
                return true
            }
        }
        return false
    }

    func collectionView(_: NSCollectionView, didSelectItemsAt _: Set<IndexPath>) {
        previewPanel?.reloadData()
    }

    //////////////////////////////////////////////////// Quicklook

    @MainActor
    override func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        if let currentItem = selectedItem {
            return currentItem.canPreview
        }
        return false
    }

    private var previewPanel: QLPreviewPanel?
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        previewPanel = panel
        panel.delegate = self
        panel.dataSource = self
    }

    override func endPreviewPanelControl(_: QLPreviewPanel!) {
        previewPanel = nil
    }

    func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        1
    }

    func previewPanel(_: QLPreviewPanel!, previewItemAt _: Int) -> QLPreviewItem! {
        selectedItem?.quickLookItem
    }

    func previewPanel(_: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown {
            components.keyDown(with: event)
            return true
        }
        return false
    }

    @objc func toggleQuickLookPreviewPanel(_: Any?) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        } else if let currentItem = selectedItem, currentItem.canPreview {
            QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
        }
    }

    @IBAction private func inviteButtonSelected(_ sender: NSButton) {
        if item.shareMode == .none {
            addInvites(sender)
        } else if item.isPrivateShareWithOnlyOwner {
            shareOptions(sender)
        } else {
            editInvites(sender)
        }
    }

    private func addInvites(_: Any) {
        let itemToShare = item
        guard let rootRecord = itemToShare.cloudKitRecord else { return }
        if let sharingService = NSSharingService(named: .cloudSharing) {
            let itemProvider = NSItemProvider()
            itemProvider.registerCloudKitShare { (completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) in
                Task { @MainActor in
                    do {
                        let share = try await CloudManager.share(item: itemToShare, rootRecord: rootRecord)
                        await completion(share, CloudManager.container, nil)
                    } catch {
                        await completion(nil, CloudManager.container, error)
                    }
                }
            }
            sharingService.delegate = self
            sharingService.perform(withItems: [itemProvider])

        } else if let w = view.window {
            missingService(w)
        }
    }

    private func missingService(_ w: NSWindow) {
        let a = NSAlert()
        a.messageText = "iCloud Sharing Failed"
        a.informativeText = "iCloud sharing is not available. Please check if it has been disabled due to a security policy on this system, or if iCloud is misconfigured."
        a.beginSheetModal(for: w, completionHandler: nil)
    }

    private func editInvites(_: Any) {
        guard let shareRecord = item.cloudKitShareRecord else { return }

        Task {
            let itemProvider = NSItemProvider()
            await itemProvider.registerCloudKitShare(shareRecord, container: CloudManager.container)
            if let sharingService = NSSharingService(named: .cloudSharing) {
                sharingService.delegate = self
                sharingService.subject = item.trimmedSuggestedName
                sharingService.perform(withItems: [itemProvider])
            } else if let w = view.window {
                missingService(w)
            }
        }
    }

    @IBAction private func openButtonSelected(_: NSButton) {
        item.tryOpen(from: self)
        view.window?.close()
    }

    func sharingService(_: NSSharingService, didSave share: CKShare) {
        item.cloudKitShareRecord = share
        item.postModified()
    }

    func sharingService(_: NSSharingService, didStopSharing _: CKShare) {
        let wasImported = item.isImportedShare
        item.cloudKitShareRecord = nil
        if wasImported {
            Model.delete(items: [item])
        } else {
            item.postModified()
        }
    }

    func anchoringView(for _: NSSharingService, showRelativeTo _: UnsafeMutablePointer<NSRect>, preferredEdge _: UnsafeMutablePointer<NSRectEdge>) -> NSView? {
        inviteButton
    }

    func sharingService(_: NSSharingService, sourceWindowForShareItems _: [Any], sharingContentScope _: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        view.window
    }

    private func shareOptions(_ sender: NSButton) {
        let a = NSAlert()
        a.messageText = "No Participants"
        a.informativeText = "This item is shared privately, but has no participants yet. You can edit options to make it public, invite more people, or stop sharing it."
        a.addButton(withTitle: "Cancel")
        a.addButton(withTitle: "Stop Sharing")
        a.addButton(withTitle: "Options")
        a.beginSheetModal(for: view.window!) { [weak self] response in
            guard let self else { return }
            if response.rawValue == 1002 {
                editInvites(sender)
            } else if response.rawValue == 1001 {
                deleteShare(sender)
            }
        }
    }

    private func deleteShare(_ sender: NSButton) {
        sender.isEnabled = false
        Task { @MainActor in
            do {
                try await CloudManager.deleteShare(item)
            } catch {
                await genericAlert(title: "Error", message: error.localizedDescription)
            }
            sender.isEnabled = true
        }
    }
}
