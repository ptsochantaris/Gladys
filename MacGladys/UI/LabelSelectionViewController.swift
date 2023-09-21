import AppKit
import GladysCommon
import GladysUI

final class LabelSelectionViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var presentingGladysVc: ViewController {
        self.presentingViewController as! ViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(labelsUpdated), name: .ModelDataUpdated, object: nil)
        labelsUpdated()
    }

    override var preferredContentSize: NSSize {
        get {
            NSSize(width: 200, height: presentingGladysVc.view.frame.size.height)
        }
        set {}
    }

    func numberOfRows(in _: NSTableView) -> Int {
        filteredLabels.count
    }

    private var filteredLabels: [Filter.Toggle] {
        let text = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let toggles = presentingGladysVc.filter.labelToggles.filter { $0.count > 0 }
        if text.isEmpty {
            return toggles
        } else {
            return toggles.filter { $0.function.displayText.localizedCaseInsensitiveContains(text) }
        }
    }

    func tableView(_: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let item = filteredLabels[row]
        let cell = tableColumn?.dataCell as? NSButtonCell
        let title = NSMutableAttributedString(string: item.function.displayText + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular)),
            .foregroundColor: NSColor.labelColor
        ])
        let itemCount = item.count == 1 ? "1 item" : "\(item.count) items"
        let subtitle = NSAttributedString(string: itemCount, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .mini)),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        title.append(subtitle)
        cell?.attributedTitle = title
        cell?.integerValue = item.active ? 1 : 0
        return cell
    }

    func tableView(_: NSTableView, setObjectValue object: Any?, for _: NSTableColumn?, row: Int) {
        var item = filteredLabels[row]
        item.active = (object as? Int == 1)
        presentingGladysVc.filter.updateLabel(item)
        sendNotification(name: .LabelSelectionChanged, object: nil)
        labelsUpdated()
    }

    @IBOutlet private var clearAllButton: NSButton!
    @IBOutlet private var tableView: NSTableView!
    @IBOutlet private var searchField: NSSearchField!

    @IBAction private func clearAllSelected(_: NSButton) {
        presentingGladysVc.filter.disableAllLabels()
        sendNotification(name: .LabelSelectionChanged, object: nil)
        labelsUpdated()
    }

    @objc private func labelsUpdated() {
        tableView.reloadData()
        clearAllButton.isEnabled = presentingGladysVc.filter.isFilteringLabels
    }

    func controlTextDidChange(_: Notification) {
        tableView.reloadData()
    }

    @IBAction private func renameLabelSelected(_: NSMenuItem) {
        let index = tableView.clickedRow
        let toggle = filteredLabels[index]
        let name = toggle.function.displayText

        let a = NSAlert()
        a.messageText = "Rename '\(name)'?"
        a.informativeText = "This will change it on all items that contain it."
        a.addButton(withTitle: "Rename")
        a.addButton(withTitle: "Cancel")
        let label = NSTextField(frame: NSRect(x: 0, y: 32, width: 290, height: 24))
        label.stringValue = name
        a.accessoryView = label
        a.window.initialFirstResponder = label
        a.beginSheetModal(for: view.window!) { [weak self] response in
            guard let self else { return }
            if response.rawValue == 1000 {
                let text = label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    presentingGladysVc.filter.renameLabel(name, to: text)
                    tableView.reloadData()
                }
            }
        }
    }

    @IBAction private func deleteLabelSelected(_: NSMenuItem) {
        let index = tableView.clickedRow
        let toggle = filteredLabels[index]
        let name = toggle.function.displayText

        confirm(
            title: "Are you sure?",
            message: "This will remove the label '\(name)' from any item that contains it.",
            action: "Remove From All Items",
            cancel: "Cancel"
        ) { [weak self] confirmed in
            if let self, confirmed {
                presentingGladysVc.filter.removeLabel(name)
                tableView.reloadData()
            }
        }
    }

    private func confirm(title: String, message: String, action: String, cancel: String, completion: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: action)
        a.addButton(withTitle: cancel)
        a.beginSheetModal(for: view.window!) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }
}
