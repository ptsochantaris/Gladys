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

	@IBOutlet private weak var labels: NSTableView!
	@IBOutlet private weak var labelField: NSTextField!

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

	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		if commandSelector.description == "insertNewline:" {
			let s = labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			if !s.isEmpty {
				done(s)
				return true
			}
		}
		return false
	}

	override func complete(_ sender: Any?) {
		super.complete(sender)
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return filteredLabels.count
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		let cell = tableColumn?.dataCell as? NSTextFieldCell
		cell?.title = filteredLabels[row].name
		return cell
	}

	func tableViewSelectionIsChanging(_ notification: Notification) {
		if let selected = labels.selectedRowIndexes.first {
			let item = filteredLabels[selected]
			labelField.stringValue = item.name
			labels.reloadData()
			done(item.name)
		}
	}

	private func done(_ label: String) {
		delegate?.newLabelController(self, selectedLabel: label)
		dismiss(nil)
	}
}
