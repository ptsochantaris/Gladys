import Cocoa

protocol NewLabelControllerDelegate: AnyObject {
    func newLabelController(_ newLabelController: NewLabelController, selectedLabel label: String)
}

final class NewLabelController: NSViewController, NSTextFieldDelegate, NSOutlineViewDelegate, NSOutlineViewDataSource {
    @IBOutlet private var labelField: NSTextField!
    @IBOutlet private var labelList: NSOutlineView!

    var associatedFilter: Filter?

    weak var delegate: NewLabelControllerDelegate?

    private var sections = [Filter.Toggle.Section]()

    var exclude = Set<String>()

    override func viewDidLoad() {
        super.viewDidLoad()
        update()
    }

    private func update() {
        guard let associatedFilter else { return }

        sections.removeAll()

        let filter = labelField.stringValue
        if filter.isEmpty {
            let recent = Filter.Toggle.Section.latestLabels.filter { !exclude.contains($0) && !$0.isEmpty }.prefix(3)
            if !recent.isEmpty {
                sections.append(Filter.Toggle.Section.filtered(labels: Array(recent), title: "Recent"))
            }
            let s = associatedFilter.labelToggles.compactMap { toggle -> String? in
                if case let .userLabel(text) = toggle.function {
                    return text
                }
                return nil
            }
            sections.append(Filter.Toggle.Section.filtered(labels: s, title: "All Labels"))
        } else {
            let s = associatedFilter.labelToggles.compactMap { toggle -> String? in
                if case let .userLabel(text) = toggle.function, text.localizedCaseInsensitiveContains(filter) {
                    return text
                }
                return nil
            }
            sections.append(Filter.Toggle.Section.filtered(labels: s, title: "Suggested Labels"))
        }

        labelList.reloadData()
        labelList.expandItem(nil, expandChildren: true)
    }

    func controlTextDidChange(_: Notification) {
        update()
    }

    func control(_: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector.description == "insertNewline:" {
            let s = labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty {
                done(s)
                return true
            }
        }
        return false
    }

    private func done(_ label: String) {
        var latest = Filter.Toggle.Section.latestLabels
        if let i = latest.firstIndex(of: label) {
            latest.remove(at: i)
        }
        latest.insert(label, at: 0)
        Filter.Toggle.Section.latestLabels = Array(latest.prefix(10))

        delegate?.newLabelController(self, selectedLabel: label)
        dismiss(nil)
    }

    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let s = item as? Filter.Toggle.Section {
            return s.labels.count
        }
        return sections.count
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let s = item as? Filter.Toggle.Section {
            return s.labels[index]
        }
        return sections[index]
    }

    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is Filter.Toggle.Section
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor _: NSTableColumn?, item: Any) -> NSView? {
        let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "LabelCell"), owner: self) as! NSTableCellView
        if let section = item as? Filter.Toggle.Section {
            view.textField?.stringValue = section.title
        } else {
            view.textField?.stringValue = item as? String ?? ""
        }
        return view
    }

    func outlineView(_: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !(item is Filter.Toggle.Section)
    }

    func outlineViewSelectionDidChange(_: Notification) {
        if let label = labelList.item(atRow: labelList.selectedRow) as? String, !label.isEmpty {
            done(label)
        }
    }
}
