//
//  DetailController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 05/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

final class DetailController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {

	@IBOutlet weak var titleField: NSTextField!
	@IBOutlet weak var notesField: NSTextField!
	@IBOutlet weak var components: NSScrollView!

	@IBOutlet weak var labels: NSTableView!
	@IBOutlet weak var labelAdd: NSButton!
	@IBOutlet weak var labelRemove: NSButton!

	private var item: ArchivedDropItem {
		return representedObject as! ArchivedDropItem
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		updateInfo()
		labels.delegate = self
		labels.dataSource = self
	}

	private func updateInfo() {
		view.window?.title = item.displayText.0 ?? "Details"
		titleField.placeholderString = item.nonOverridenText.0 ?? "Title"
		titleField.stringValue = item.titleOverride
		notesField.stringValue = item.note
	}

	override func viewWillDisappear() {
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
			item.markUpdated()
			item.postModified()
			item.reIndex()
			Model.save()
		}
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

	private var notesDirty = false, titleDirty = false
	override func controlTextDidChange(_ obj: Notification) {
		guard let o = obj.object as? NSTextField else { return }
		if o == notesField {
			notesDirty = true
		} else if o == titleField {
			titleDirty = true
		}
	}
}
