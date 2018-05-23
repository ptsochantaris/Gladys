//
//  LabelSelectionViewController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 04/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa

final class LabelSelectionViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

	override func viewDidLoad() {
		super.viewDidLoad()
		NotificationCenter.default.addObserver(self, selector: #selector(labelsUpdated), name: .ExternalDataUpdated, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(labelsUpdated), name: .SaveComplete, object: nil)
		labelsUpdated()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override var preferredContentSize: NSSize {
		set {}
		get {
			return NSSize(width: 200, height: ViewController.shared.view.bounds.size.height)
		}
	}

	override func viewWillDisappear() {
		super.viewWillDisappear()
		ViewController.shared.labelsDone()
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return filteredLabels.count
	}

	private var filteredLabels: [Model.LabelToggle] {
		let text = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		if text.isEmpty {
			return Model.labelToggles
		} else {
			return Model.labelToggles.filter { $0.name.localizedCaseInsensitiveContains(text) }
		}
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		let item = filteredLabels[row]
		let cell = tableColumn?.dataCell as? NSButtonCell
		let title = NSMutableAttributedString(string: item.name + "\n", attributes: [
			NSAttributedStringKey.font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular)),
			NSAttributedStringKey.foregroundColor: NSColor.labelColor,
			])
		let itemCount = item.count == 1 ? "1 item" : "\(item.count) items"
		let subtitle = NSAttributedString(string: itemCount, attributes: [
			NSAttributedStringKey.font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .mini)),
			NSAttributedStringKey.foregroundColor: NSColor.secondaryLabelColor,
			])
		title.append(subtitle)
		cell?.attributedTitle = title
		cell?.integerValue = item.enabled ? 1 : 0
		return cell
	}

	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		var item = filteredLabels[row]
		item.enabled = (object as? Int == 1)
		Model.updateLabel(item)
		NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
		labelsUpdated()
	}

	@IBOutlet weak var clearAllButton: NSButton!
	@IBOutlet weak var tableView: NSTableView!
	@IBOutlet weak var searchField: NSSearchField!

	@IBAction func clearAllSelected(_ sender: NSButton) {
		Model.disableAllLabels()
		NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
		labelsUpdated()
	}

	@objc private func labelsUpdated() {
		tableView.reloadData()
		clearAllButton.isEnabled = Model.isFilteringLabels
	}

	override func controlTextDidChange(_ obj: Notification) {
		tableView.reloadData()
	}
}
