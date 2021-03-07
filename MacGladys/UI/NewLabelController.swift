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

	@IBOutlet private var labelField: NSTextField!
    @IBOutlet private var labelList: NSOutlineView!
    
	weak var delegate: NewLabelControllerDelegate?
    
    private var sections = [ModelFilterContext.LabelToggle.Section]()
    
    var exclude = Set<String>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        update()
    }

    private func update() {
        sections.removeAll()
        
        let filter = labelField.stringValue
        if filter.isEmpty {
            let recent = ModelFilterContext.LabelToggle.Section.latestLabels.filter { !exclude.contains($0) && !$0.isEmpty }.prefix(3)
            if !recent.isEmpty {
                sections.append(ModelFilterContext.LabelToggle.Section.filtered(labels: Array(recent), title: "Recent"))
            }
            let s = Model.sharedFilter.labelToggles.compactMap { $0.emptyChecker ? nil : $0.name }
            sections.append(ModelFilterContext.LabelToggle.Section.filtered(labels: s, title: "All Labels"))
        } else {
            let s = Model.sharedFilter.labelToggles.compactMap { $0.name.localizedCaseInsensitiveContains(filter) && !$0.emptyChecker ? $0.name : nil }
            sections.append(ModelFilterContext.LabelToggle.Section.filtered(labels: s, title: "Suggested Labels"))
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
        var latest = ModelFilterContext.LabelToggle.Section.latestLabels
        if let i = latest.firstIndex(of: label) {
            latest.remove(at: i)
        }
        latest.insert(label, at: 0)
        ModelFilterContext.LabelToggle.Section.latestLabels = Array(latest.prefix(10))

		delegate?.newLabelController(self, selectedLabel: label)
		dismiss(nil)
	}
        
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let s = item as? ModelFilterContext.LabelToggle.Section {
            return s.labels.count
        }
        return sections.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let s = item as? ModelFilterContext.LabelToggle.Section {
            return s.labels[index]
        }
        return sections[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is ModelFilterContext.LabelToggle.Section
    }
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "LabelCell"), owner: self) as! NSTableCellView
        if let section = item as? ModelFilterContext.LabelToggle.Section {
            view.textField?.stringValue = section.title
        } else {
            view.textField?.stringValue = item as? String ?? ""
        }
        return view
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return !(item is ModelFilterContext.LabelToggle.Section)
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if let label = labelList.item(atRow: labelList.selectedRow) as? String, !label.isEmpty {
            done(label)
        }
    }
}
