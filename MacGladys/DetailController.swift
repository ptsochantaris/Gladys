//
//  DetailController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 05/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

final class ComponentCollectionView: NSCollectionView {}

final class DetailController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NewLabelControllerDelegate, NSCollectionViewDelegate, NSCollectionViewDataSource, ComponentCellDelegate {

	@IBOutlet weak var titleField: NSTextField!
	@IBOutlet weak var notesField: NSTextField!

	@IBOutlet weak var labels: NSTableView!
	@IBOutlet weak var labelAdd: NSButton!
	@IBOutlet weak var labelRemove: NSButton!

	@IBOutlet weak var components: NSCollectionView!
	private let componentCellId = NSUserInterfaceItemIdentifier("ComponentCell")

	override func viewDidLoad() {
		super.viewDidLoad()
		NotificationCenter.default.addObserver(self, selector: #selector(updateInfo), name: .ItemModified, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(checkForRemoved), name: .SaveComplete, object: nil)

		components.registerForDraggedTypes([NSPasteboard.PasteboardType(kUTTypeItem as String), NSPasteboard.PasteboardType(kUTTypeContent as String)])
		components.setDraggingSourceOperationMask(.move, forLocal: true)
		components.setDraggingSourceOperationMask(.copy, forLocal: false)

		labels.registerForDraggedTypes([NSPasteboard.PasteboardType(kUTTypeText as String)])
		labels.setDraggingSourceOperationMask(.move, forLocal: true)
		labels.setDraggingSourceOperationMask(.copy, forLocal: false)
	}

	private var lastUpdate = Date.distantPast

	@objc func checkForRemoved() {
		if Model.item(uuid: item.uuid) == nil {
			view.window?.close()
		} else if lastUpdate != item.updatedAt {
			updateInfo()
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	private var item: ArchivedDropItem {
		return representedObject as! ArchivedDropItem
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		updateInfo()
		labels.delegate = self
		labels.dataSource = self

		let activity = NSUserActivity(activityType: kGladysDetailViewingActivity)
		activity.title = item.displayTitleOrUuid
		activity.isEligibleForSearch = false
		activity.isEligibleForHandoff = true
		activity.isEligibleForPublicIndexing = false
		userActivity = activity
	}

	@objc private func updateInfo() {
		view.window?.title = item.displayText.0 ?? "Details"
		titleField.placeholderString = item.nonOverridenText.0 ?? "Title"
		titleField.stringValue = item.titleOverride
		notesField.stringValue = item.note
		labels.reloadData()
		updateLabelButtons()
		components.animator().reloadData()
		lastUpdate = item.updatedAt
	}

	override func viewWillDisappear() {
		done()
		super.viewWillDisappear()
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return item.labels.count
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		let cell = tableColumn?.dataCell as? NSTextFieldCell
		cell?.title = item.labels[row]
		return cell
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		updateLabelButtons()
	}

	func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
		let p = NSPasteboardItem()
		p.setString(item.labels[row], forType: NSPasteboard.PasteboardType(kUTTypeText as String))
		return p
	}

	func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
		return dropOperation == .above ? .move : []
	}

	func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
		let p = info.draggingPasteboard()
		guard let label = p.string(forType: NSPasteboard.PasteboardType(kUTTypeText as String)) ??
			p.string(forType: NSPasteboard.PasteboardType(kUTTypePlainText as String)) ??
			p.string(forType: NSPasteboard.PasteboardType(kUTTypeUTF8PlainText as String)) else { return false }

		var newIndex = row

		if let oldIndex = item.labels.index(of: label) {
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
		return true
	}

	private func updateLabelButtons() {
		removeButton.isEnabled = labels.selectedRowIndexes.count > 0
	}

	private var notesDirty = false, titleDirty = false
	override func controlTextDidChange(_ obj: Notification) {
		guard let o = obj.object as? NSTextField else { return }
		if o == notesField {
			notesDirty = true
		} else if o == titleField {
			titleDirty = true
		}
	}

	override func controlTextDidEndEditing(_ obj: Notification) {
		done()
	}

	@IBOutlet weak var removeButton: NSButton!
	@IBAction func removeSelected(_ sender: NSButton) {
		if let selected = labels.selectedRowIndexes.first {
			item.labels.remove(at: selected)
			saveItem()
			labels.selectRowIndexes([], byExtendingSelection: false)
		}
	}

	private func saveItem() {
		if Model.item(uuid: item.uuid) == nil {
			return
		}
		item.markUpdated()
		item.postModified()
		item.reIndex()
		Model.save()
	}

	private func done() {
		var dirty = false
		if notesDirty {
			item.note = notesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			dirty = true
		}
		if titleDirty {
			item.titleOverride = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			dirty = true
		}
		if dirty {
			saveItem()
		}
	}

	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if let d = segue.destinationController as? NewLabelController {
			d.delegate = self
		}
	}

	func newLabelController(_ newLabelController: NewLabelController, selectedLabel label: String) {
		if !item.labels.contains(label) {
			item.labels.append(label)
			saveItem()
		}
	}

	override func updateUserActivityState(_ userActivity: NSUserActivity) {
		super.updateUserActivityState(userActivity)
		userActivity.userInfo = [kGladysDetailViewingActivityItemUuid: item.uuid]
	}

	func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
		return item.typeItems.count
	}

	func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
		let i = collectionView.makeItem(withIdentifier: componentCellId, for: indexPath) as! ComponentCell
		i.delegate = self
		i.representedObject = item.typeItems[indexPath.item]
		return i
	}

	private func copy(item: ArchivedDropItemType) {
		let p = NSPasteboard.general
		p.clearContents()
		p.writeObjects([item.pasteboardItem])
	}

	private func delete(at index: Int) {
		let component = item.typeItems[index]
		item.typeItems.remove(at: index)
		component.deleteFromStorage()
		item.renumberTypeItems()
		components.animator().deleteItems(at: [IndexPath(item: index, section: 0)])
		saveItem()
	}

	func componentCell(_ componentCell: ComponentCell, wants action: ComponentCell.Action) {
		guard let i = componentCell.representedObject as? ArchivedDropItemType, let index = item.typeItems.index(of: i) else { return }

		components.deselectAll(nil)
		components.selectItems(at: [IndexPath(item: index, section: 0)], scrollPosition: [])

		switch action {
		case .open:
			i.tryOpen(from: self)
		case .copy:
			copy(item: i)
		case .delete:
			delete(at: index)
		case .archive:
			archive(nil)
		case .share:
			shareSelected(i)
		}
	}

	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(archive(_:)):
			let count = components.selectionIndexPaths.count
			if count == 0 { return false }
			let selectedComponentsThatCanBeArchived = components.selectionIndexPaths.filter { item.typeItems[$0.item].isArchivable }
			return selectedComponentsThatCanBeArchived.count == count
		case #selector(copy(_:)), #selector(delete(_:)), #selector(open(_:)), #selector(shareSelected(_:)):
			return components.selectionIndexes.count > 0
		default:
			return true
		}
	}

	@objc func copy(_ sender: Any?) {
		if let i = components.selectionIndexes.first {
			copy(item: item.typeItems[i])
		}
	}

	@objc func open(_ sender: Any?) {
		if let i = components.selectionIndexes.first {
			item.typeItems[i].tryOpen(from: self)
		}
	}

	@objc func delete(_ sender: Any?) {
		if let i = components.selectionIndexes.first {
			delete(at: i)
		}
	}

	@objc func shareSelected(_ sender: Any?) {
		guard let i = components.selectionIndexes.first,
			let cell = components.item(at: IndexPath(item: i, section: 0)),
			let itemToShare = cell.representedObject as? ArchivedDropItemType,
			let shareableItem = itemToShare.itemForShare.0
			else { return }

		let p = NSSharingServicePicker(items: [shareableItem])
		let f = cell.view.frame
		let centerFrame = NSRect(origin: CGPoint(x: f.midX-1, y: f.midY-1), size: CGSize(width: 2, height: 2))
		DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
			p.show(relativeTo: centerFrame, of: self.components, preferredEdge: .minY)
		}
	}

	@objc func archive(_ sender: Any?) {
		guard let i = components.selectionIndexes.first else { return }
		let component = item.typeItems[i]
		guard let url = component.encodedUrl as URL?, let cell = components.item(at: IndexPath(item: i, section: 0)) as? ComponentCell else { return }
		cell.animateArchiving = true

		WebArchiver.archiveFromUrl(url) { data, typeIdentifier, error in
			if let error = error {
				DispatchQueue.main.async {
					genericAlert(title: "Archiving failed", message: error.finalDescription, on: self)
				}
			} else if let data = data, let typeIdentifier = typeIdentifier {
				let newTypeItem = ArchivedDropItemType(typeIdentifier: typeIdentifier, parentUuid: self.item.uuid, data: data, order: self.item.typeItems.count)
				DispatchQueue.main.async {
					self.item.typeItems.append(newTypeItem)
					self.saveItem()
				}
			}
			DispatchQueue.main.async {
				cell.animateArchiving = false
			}
		}
	}

	override func viewWillLayout() {
		super.viewWillLayout()

		let w = components.frame.size.width
		let columns = (w / 250.0).rounded(.down)
		let s = ((w - ((columns+1) * 10)) / columns).rounded(.down)
		(components.collectionViewLayout as! NSCollectionViewFlowLayout).itemSize = NSSize(width: s, height: 89)
	}

	func collectionView(_ collectionView: NSCollectionView, writeItemsAt indexPaths: Set<IndexPath>, to pasteboard: NSPasteboard) -> Bool {
		let pasteboardItems = indexPaths.map { item.typeItems[$0.item].pasteboardItem }
		pasteboard.writeObjects(pasteboardItems)
		let filePromises = indexPaths.compactMap { item.typeItems[$0.item].filePromise }
		if !filePromises.isEmpty {
			pasteboard.writeObjects(filePromises)
		}
		return true
	}

	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
		return true
	}

	func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
		if draggingInfo.draggingSource() is ComponentCollectionView {
			proposedDropOperation.pointee = .on
			return collectionView == components ? .move : .copy
		} else {
			return []
		}
	}

	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
		draggingIndexPaths = Array(indexPaths)
	}

	private var draggingIndexPaths: [IndexPath]?

	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
		draggingIndexPaths = nil
	}

	func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
		if let s = draggingInfo.draggingSource() as? ComponentCollectionView {

			let destinationIndex = indexPath.item
			if s == collectionView, let draggingIndexPath = draggingIndexPaths?.first {
				let sourceItem = item.typeItems[draggingIndexPath.item]
				let sourceIndex = draggingIndexPath.item
				item.typeItems.remove(at: sourceIndex)
				item.typeItems.insert(sourceItem, at: destinationIndex)
				item.renumberTypeItems()
				components.animator().moveItem(at: draggingIndexPath, to: indexPath)
				components.deselectAll(nil)
				saveItem()
				return true

			} else if let pasteboardItem = draggingInfo.draggingPasteboard().pasteboardItems?.first, let type = pasteboardItem.types.first, let data = pasteboardItem.data(forType: type) {
				let typeItem = ArchivedDropItemType(typeIdentifier: type.rawValue, parentUuid: item.uuid, data: data, order: 99999)
				item.typeItems.insert(typeItem, at: destinationIndex)
				item.needsReIngest = true
				item.renumberTypeItems()
				components.animator().insertItems(at: [indexPath])
				saveItem()
				return true
			}
		}
		return false
	}
}
