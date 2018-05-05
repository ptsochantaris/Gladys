//
//  DetailController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 05/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

final class DetailController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NewLabelControllerDelegate, NSCollectionViewDelegate, NSCollectionViewDataSource {

	@IBOutlet weak var titleField: NSTextField!
	@IBOutlet weak var notesField: NSTextField!

	@IBOutlet weak var moveLabelUpButton: NSButton!
	@IBOutlet weak var moveLabelDownButton: NSButton!

	@IBOutlet weak var labels: NSTableView!
	@IBOutlet weak var labelAdd: NSButton!
	@IBOutlet weak var labelRemove: NSButton!

	@IBOutlet weak var components: NSCollectionView!
	private let componentCellId = NSUserInterfaceItemIdentifier("ComponentCell")

	override func viewDidLoad() {
		super.viewDidLoad()
		NotificationCenter.default.addObserver(self, selector: #selector(updateInfo), name: .ItemModified, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(checkForRemoved), name: .SaveComplete, object: nil)

		components.registerForDraggedTypes([NSPasteboard.PasteboardType(kUTTypeItem as String)])
		components.setDraggingSourceOperationMask(.move, forLocal: true)
		components.setDraggingSourceOperationMask(.copy, forLocal: false)
	}

	@objc func checkForRemoved() {
		if Model.item(uuid: item.uuid) == nil {
			view.window?.close()
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

	private func updateLabelButtons() {
		if let selected = labels.selectedRowIndexes.first {
			removeButton.isEnabled = labels.selectedRowIndexes.count > 0
			moveLabelDownButton.isEnabled = selected < item.labels.count - 1
			moveLabelUpButton.isEnabled = selected > 0
		} else {
			removeButton.isEnabled = false
			moveLabelUpButton.isEnabled = false
			moveLabelDownButton.isEnabled = false
		}
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
			labels.reloadData()
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
			labels.reloadData()
		}
	}

	@IBAction func labelMoveUpButtonSelected(_ sender: NSButton) {
		if let selected = labels.selectedRowIndexes.first, selected > 0 {
			item.labels.swapAt(selected, selected-1)
			labels.reloadData()
			saveItem()
			labels.selectRowIndexes(IndexSet(integer: selected-1), byExtendingSelection: false)
		}
	}

	@IBAction func labelMoveDownButtonSelected(_ sender: NSButton) {
		if let selected = labels.selectedRowIndexes.first, selected < item.labels.count - 1 {
			item.labels.swapAt(selected, selected+1)
			labels.reloadData()
			saveItem()
			labels.selectRowIndexes(IndexSet(integer: selected+1), byExtendingSelection: false)
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
		let i = collectionView.makeItem(withIdentifier: componentCellId, for: indexPath)
		i.representedObject = item.typeItems[indexPath.item]
		return i
	}

	override func viewWillLayout() {
		super.viewWillLayout()

		let w = components.frame.size.width
		let columns = (w / 250.0).rounded(.down)
		let s = ((w - ((columns+1) * 10)) / columns).rounded(.down)
		(components.collectionViewLayout as! NSCollectionViewFlowLayout).itemSize = NSSize(width: s, height: 89)
	}

	func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
		return item.typeItems[indexPath.item].pasteboardWriter
	}

	func collectionView(_ collectionView: NSCollectionView, writeItemsAt indexPaths: Set<IndexPath>, to pasteboard: NSPasteboard) -> Bool {
		let writers = indexPaths.map { item.typeItems[$0.item].pasteboardWriter }
		pasteboard.writeObjects(writers)
		return true
	}

	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
		return true
	}

	func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
		if let s = draggingInfo.draggingSource() as? NSCollectionView, s == collectionView {
			proposedDropOperation.pointee = .before
			return .move
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
		if let s = draggingInfo.draggingSource() as? NSCollectionView, s == collectionView, let draggingIndexPath = draggingIndexPaths?.first {

			let sourceItem = item.typeItems[draggingIndexPath.item]
			let sourceIndex = draggingIndexPath.item
			var destinationIndex = indexPath.item
			if destinationIndex > sourceIndex {
				destinationIndex -= 1
			}
			item.typeItems.remove(at: sourceIndex)
			item.typeItems.insert(sourceItem, at: destinationIndex)
			item.renumberTypeItems()
			saveItem()

			components.reloadData()
			return true
		}

		return false
	}
}
