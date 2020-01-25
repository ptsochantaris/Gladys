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

final class NewLabelController: NSViewController, NSTextFieldDelegate, NSOutlineViewDelegate, NSOutlineViewDataSource {

	@IBOutlet private weak var labelField: NSTextField!
    @IBOutlet private weak var labelList: NSOutlineView!
    
	weak var delegate: NewLabelControllerDelegate?

    private enum Section {
        case recent(labels: [String], title: String)
        case filtered(labels: [String], title: String)
    }
    
    private var sections = [Section]()
    
    var exclude = Set<String>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        update()
    }

    private func update() {
        sections.removeAll()
        
        let filter = labelField.stringValue
        if filter.isEmpty {
            let recent = latestLabels.filter { !exclude.contains($0) }.prefix(3)
            if !recent.isEmpty {
                sections.append(Section.filtered(labels: Array(recent), title: "Recent Labels"))
            }
            let s = Model.sharedFilter.labelToggles.compactMap { $0.emptyChecker ? nil : $0.name }
            sections.append(Section.filtered(labels: s, title: "All Labels"))
        } else {
            let s = Model.sharedFilter.labelToggles.compactMap { $0.name.localizedCaseInsensitiveContains(filter) && !$0.emptyChecker ? $0.name : nil }
            sections.append(Section.filtered(labels: s, title: "Suggested Labels"))
        }
        
        labelList.reloadData()
        labelList.expandItem(nil, expandChildren: true)
    }
    
	func controlTextDidChange(_ obj: Notification) {
        update()
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

	private func done(_ label: String) {
		delegate?.newLabelController(self, selectedLabel: label)
		dismiss(nil)
	}
    
    private var latestLabels = UserDefaults.standard.object(forKey: "latestLabels") as? [String] ?? [] {
        didSet {
            UserDefaults.standard.set(latestLabels, forKey: "latestLabels")
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let s = item as? Section {
            switch s {
            case .filtered(let labels, _), .recent(let labels, _):
                return labels.count
            }
        }
        return sections.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let s = item as? Section {
            switch s {
            case .filtered(let labels, _), .recent(let labels, _):
                return labels[index]
            }
        }
        return sections[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let s = item as? Section {
            switch s {
            case .filtered(let labels, _), .recent(let labels, _):
                return !labels.isEmpty
            }
        }
        return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "LabelCell"), owner: self) as! NSTableCellView
        if let section = item as? Section {
            switch section {
            case .filtered(_, let title), .recent(_, let title):
                view.textField?.stringValue = title
            }
        } else {
            view.textField?.stringValue = item as? String ?? ""
        }
        view.textField?.sizeToFit()
        return view
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return !(item is Section)
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if let label = labelList.item(atRow: labelList.selectedRow) as? String {
            var latest = latestLabels
            if let i = latest.firstIndex(of: label) {
                latest.remove(at: i)
            }
            latest.insert(label, at: 0)
            latestLabels = Array(latest.prefix(10))
            done(label)
        }
    }
}
