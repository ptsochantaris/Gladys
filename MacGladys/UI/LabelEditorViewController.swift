import AppKit
import GladysCommon
import GladysUI

final class LabelEditorViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    @IBOutlet private var tableView: NSTableView!
    @IBOutlet private var newLabelField: NSTextField!
    @IBOutlet var togglesColumn: NSTableColumn!

    var associatedFilter: Filter?

    func numberOfRows(in _: NSTableView) -> Int {
        availableToggles.count
    }

    private lazy var allToggles: [Filter.Toggle] = associatedFilter?.labelToggles.filter { $0.function != .unlabeledItems } ?? []

    private var availableToggles: [Filter.Toggle] {
        let filter = newLabelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if filter.isEmpty {
            return allToggles
        } else {
            return allToggles.filter { $0.function.displayText.localizedCaseInsensitiveContains(filter) }
        }
    }

    var selectedItems: [UUID]?
    var editedUUIDs = Set<UUID>()

    func tableView(_: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let item = availableToggles[row]
        let cell = tableColumn?.dataCell as? NSButtonCell

        let title = NSMutableAttributedString(string: item.function.displayText, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular)),
            .foregroundColor: NSColor.labelColor
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

    func control(_: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
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

    func controlTextDidChange(_: Notification) {
        tableView.reloadData()
    }

    private func addNewLabel(_ newTag: String) {
        newLabelField.stringValue = ""
        let function = Filter.Toggle.Function.userLabel(newTag)
        if !allToggles.contains(where: { $0.function == function }) {
            let newToggle = Filter.Toggle(function: function, count: selectedItems?.count ?? 0, active: false, currentDisplayMode: .collapsed, preferredDisplayMode: .scrolling)
            allToggles.append(newToggle)
            allToggles.sort { $0.function.displayText.localizedCaseInsensitiveCompare($1.function.displayText) == .orderedAscending }
        }
        tableView.reloadData()
        if let i = allToggles.firstIndex(where: { $0.function == function }) {
            let existingToggle = allToggles[i]
            if existingToggle.toggleState(across: selectedItems) != .all {
                tableView(tableView, setObjectValue: NSButton.StateValue.on, for: togglesColumn, row: i)
            }
            tableView.scrollRowToVisible(i)
        }
    }

    func tableView(_ tableView: NSTableView, setObjectValue _: Any?, for _: NSTableColumn?, row: Int) {
        guard let selectedItems else { return }
        let toggle = availableToggles[row]
        let state = toggle.toggleState(across: selectedItems)
        let name = toggle.function.displayText
        switch state {
        case .none:
            selectedItems.forEach {
                if let item = DropStore.item(uuid: $0) {
                    item.labels.append(name)
                    item.postModified()
                    editedUUIDs.insert($0)
                }
            }
        case .some:
            selectedItems.forEach {
                if let item = DropStore.item(uuid: $0), !item.labels.contains(name) {
                    item.labels.append(name)
                    item.postModified()
                    editedUUIDs.insert($0)
                }
            }
        case .all:
            selectedItems.forEach {
                if let item = DropStore.item(uuid: $0), let i = item.labels.firstIndex(of: name) {
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
            if let i = DropStore.item(uuid: uuid) {
                i.markUpdated()
                hadChanges = true
            }
        }
        if hadChanges {
            Task {
                await Model.save()
            }
        }
    }
}
