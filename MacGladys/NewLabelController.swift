//
//  NewLabelController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 05/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

protocol NewLabelControllerDelegate: class {
	func newLabelController(_ newLabelController: NewLabelController, selectedLabel label: String)
}

final class NewLabelController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate {

	@IBOutlet weak var labels: NSTableView!
	@IBOutlet weak var labelField: NSTextField!

	weak var delegate: NewLabelControllerDelegate?

	private var filteredLabels: [Model.LabelToggle] {
		let l = labelField.stringValue
		if l.isEmpty {
			return Model.labelToggles.filter { !$0.emptyChecker }
		} else {
			return Model.labelToggles.filter { !$0.emptyChecker && $0.name.localizedCaseInsensitiveContains(l) }
		}
	}

	override func controlTextDidChange(_ obj: Notification) {
		labels.reloadData()
	}

	override func controlTextDidEndEditing(_ obj: Notification) {
		let s = labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		if !s.isEmpty {
			done(s)
		}
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return filteredLabels.count
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		let cell = tableColumn?.dataCell as? NSTextFieldCell
		cell?.title = filteredLabels[row].name
		return cell
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		if let selected = labels.selectedRowIndexes.first {
			let item = filteredLabels[selected]
			done(item.name)
		}
	}

	private func done(_ label: String) {
		delegate?.newLabelController(self, selectedLabel: label)
		dismiss(self)
	}
}
