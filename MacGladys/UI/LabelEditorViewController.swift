import AppKit

final class LabelEditorViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

	@IBOutlet private weak var tableView: NSTableView!
	@IBOutlet private weak var newLabelField: NSTextField!
	@IBOutlet weak var togglesColumn: NSTableColumn!

	func numberOfRows(in tableView: NSTableView) -> Int {
		return availableToggles.count
	}

	private var allToggles: [ModelFilterContext.LabelToggle] = {
		return Model.sharedFilter.labelToggles.filter { !$0.emptyChecker }
	}()

	private var availableToggles: [ModelFilterContext.LabelToggle] {
		let filter = newLabelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		if filter.isEmpty {
			return allToggles
		} else {
			return allToggles.filter { $0.name.localizedCaseInsensitiveContains(filter) }
		}
	}

	var selectedItems: [UUID]?
	var editedUUIDs = Set<UUID>()

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {

		let item = availableToggles[row]
		let cell = tableColumn?.dataCell as? NSButtonCell

		let title = NSMutableAttributedString(string: item.name, attributes: [
			.font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular)),
			.foregroundColor: NSColor.labelColor,
			])
		cell?.attributedTitle = title

		switch item.toggleState(across: selectedItems) {
		case .all:
			cell?.state = .on
		case .some:
			cell?.state = .mixed
		case .none:
			cell?.state = .off
		}
		return cell
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		if commandSelector == #selector(cancelOperation(_:)) {
			dismiss(nil)
			return true
		}

		if commandSelector == #selector(insertNewline(_:)) {
			let newLabel = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
			if newLabel.isEmpty {
				dismiss(nil)
			} else {
				addNewLabel(newLabel)
			}
			return true
		}

		return false
	}

	func controlTextDidChange(_ obj: Notification) {
		tableView.reloadData()
	}

	private func addNewLabel(_ newTag: String) {

		newLabelField.stringValue = ""
		if !allToggles.contains(where: { $0.name == newTag }) {
			let newToggle = ModelFilterContext.LabelToggle(name: newTag, count: selectedItems?.count ?? 0, enabled: false, emptyChecker: false)
			allToggles.append(newToggle)
			allToggles.sort { $0.name < $1.name }
		}
		tableView.reloadData()
		if let i = allToggles.firstIndex(where: { $0.name == newTag }) {
			let existingToggle = allToggles[i]
			if existingToggle.toggleState(across: selectedItems) != .all {
				tableView(tableView, setObjectValue: NSButton.StateValue.on, for: togglesColumn, row: i)
			}
			tableView.scrollRowToVisible(i)
		}
	}

	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		guard let selectedItems = selectedItems else { return }
		let toggle = availableToggles[row]
		let state = toggle.toggleState(across: selectedItems)
		switch state {
		case .none:
			selectedItems.forEach {
				if let item = Model.item(uuid: $0) {
					item.labels.append(toggle.name)
					item.postModified()
					editedUUIDs.insert($0)
				}
			}
		case .some:
			selectedItems.forEach {
				if let item = Model.item(uuid: $0), !item.labels.contains(toggle.name) {
					item.labels.append(toggle.name)
					item.postModified()
					editedUUIDs.insert($0)
				}
			}
		case .all:
			selectedItems.forEach {
				if let item = Model.item(uuid: $0), let i = item.labels.firstIndex(of: toggle.name) {
					item.labels.remove(at: i)
					item.postModified()
					editedUUIDs.insert($0)
				}
			}
		}
		tableView.reloadData()
	}

	override func viewWillDisappear() {
		super.viewWillDisappear()
		var hadChanges = false
		for uuid in editedUUIDs {
			if let i = Model.item(uuid: uuid) {
				i.markUpdated()
				hadChanges = true
			}
		}
		if hadChanges {
			Model.save()
		}
	}
}
