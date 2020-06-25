//
//  LabelEditor.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 19/12/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelEditorController: GladysViewController, NotesEditorViewControllerDelegate, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate {

	@IBOutlet private weak var labelText: UITextField!
	@IBOutlet private weak var table: UITableView!

	@IBOutlet private var headerView: UIView!
	@IBOutlet private weak var headerLabel: UILabel!

	var selectedItems = [UUID]()
	var editedUUIDs = Set<UUID>()

	var endCallback: ((Bool) -> Void)?
    
    var currentFilter: ModelFilterContext!

    private var modelToggles: [ModelFilterContext.LabelToggle] {
        return currentFilter.labelToggles.filter { !$0.emptyChecker }
    }
    
	private lazy var allToggles = [ModelFilterContext.LabelToggle]()

	private var availableToggles = [ModelFilterContext.LabelToggle]()

	override func viewDidLoad() {
		super.viewDidLoad()
        labelsUpdated()
        doneButtonLocation = .left
        
        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(labelsUpdated), name: .ModelDataUpdated, object: nil)
	}
    
    @objc private func labelsUpdated() {
        allToggles = modelToggles
        updateFilter(labelText.text)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        view.backgroundColor = navigationItem.leftBarButtonItem != nil ? UIColor.systemBackground : .clear
    }

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		guard let r = navigationItem.rightBarButtonItem else { return }
		if commonNote == nil {
			r.title = "New Note"
		} else {
			let count = selectedItems.count
			r.title = count > 1 ? "Edit Notes" : "Edit Note"
		}
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return min(1, availableToggles.count)
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return availableToggles.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "LabelEditorCell") as! LabelEditorCell

		let toggle = availableToggles[indexPath.row]
		cell.labelName.text = toggle.name
		cell.accessibilityLabel = toggle.name

		let state = toggle.toggleState(across: selectedItems)
		cell.tick.isHidden = state == .none
		cell.tick.isHighlighted = state == .all
		cell.accessibilityValue = state.accessibilityValue
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let toggle = availableToggles[indexPath.row]
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
		tableView.reloadRows(at: [indexPath], with: .none)
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return 40
	}

	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		return headerView
	}

	private func updateFilter(_ text: String?) {
		let filter = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		if filter.isEmpty {
			availableToggles = allToggles
		} else {
			availableToggles = allToggles.filter { $0.name.localizedCaseInsensitiveContains(filter) }
		}
		table.reloadData()
	}

	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {

		if string != "\n" {
			if let oldText = textField.text, !oldText.isEmpty, let r = Range(range, in: oldText) {
				let newText = oldText.replacingCharacters(in: r, with: string)
				updateFilter(newText)
			} else {
				updateFilter(nil)
			}
			return true
		}

		textField.resignFirstResponder()

		guard let newTag = textField.text, !newTag.isEmpty else {
			return false
		}

		textField.text = nil
		if !allToggles.contains(where: { $0.name == newTag }) {
			let newToggle = ModelFilterContext.LabelToggle(name: newTag, count: selectedItems.count, enabled: false, emptyChecker: false)
			allToggles.append(newToggle)
			allToggles.sort { $0.name < $1.name }
		}
		updateFilter(nil)
		if let i = allToggles.firstIndex(where: { $0.name == newTag }) {
			let existingToggle = allToggles[i]
			let ip = IndexPath(row: i, section: 0)
			if existingToggle.toggleState(across: selectedItems) != .all {
				tableView(table, didSelectRowAt: ip)
			}
			table.scrollToRow(at: ip, at: .middle, animated: true)
		}
		return false
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		let count = navigationController?.viewControllers.count ?? 0
		if count > 1 { // is pushing
			return
		}
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
		endCallback?(hadChanges)
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		if UIAccessibility.isVoiceOverRunning && labelText.isFirstResponder { // weird hack for word mode
			let left = -scrollView.adjustedContentInset.left
			if scrollView.contentOffset.x < left {
				let top = -scrollView.adjustedContentInset.top
				scrollView.contentOffset = CGPoint(x: left, y: top)
			}
		}

		headerLabel.alpha = 2.0 - min(2, max(0, scrollView.contentOffset.y / 48.0))
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
		if let d = segue.destination as? NotesEditorViewController {
			d.delegate = self
			d.startupNote = commonNote
			d.title = navigationItem.rightBarButtonItem?.title
		}
	}

	private var commonNote: String? {
		if let firstItemUuid = selectedItems.first {
			let firstItem = Model.item(uuid: firstItemUuid)
			let commonNote = firstItem?.note
			for item in selectedItems where Model.item(uuid: item)?.note != commonNote {
				return nil
			}
			return commonNote
		}
		return nil
	}

	func newNoteSaved(note: String) {
		selectedItems.forEach {
			if let item = Model.item(uuid: $0) {
				item.note = note
				item.postModified()
				editedUUIDs.insert($0)
			}
		}
	}
}
