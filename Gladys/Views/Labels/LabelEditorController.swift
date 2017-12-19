//
//  LabelEditor.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 19/12/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelEditorController: GladysViewController, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate {

	@IBOutlet weak var labelText: UITextField!
	@IBOutlet weak var table: UITableView!

	@IBOutlet var headerView: UIView!
	@IBOutlet weak var headerLabel: UILabel!

	var selectedItems: [UUID]?
	var editedUUIDs = Set<UUID>()

	var endCallback: ((Bool)->Void)?

	var availableToggles: [String] = {
		return Model.labelToggles.flatMap { $0.emptyChecker ? nil : $0.name }
	}()

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setNavigationBarHidden(true, animated: false)
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return min(1, availableToggles.count)
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return availableToggles.count
	}

	enum State {
		case none, some, all
	}

	private func toggleState(for toggle: String) -> State {
		let n = selectedItems?.reduce(0) { total, uuid -> Int in
			if let item = Model.item(uuid: uuid), item.labels.contains(toggle) {
				return total + 1
			}
			return total
			} ?? 0
		if n == (selectedItems?.count ?? 0) {
			return .all
		}
		return n > 0 ? .some : .none
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "LabelEditorCell") as! LabelEditorCell

		let toggle = availableToggles[indexPath.row]
		cell.labelName.text = toggle

		let state = toggleState(for: toggle)
		cell.tick.isHidden = state == .none
		cell.tick.isHighlighted = state == .all
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		guard let selectedItems = selectedItems else { return }
		let toggle = availableToggles[indexPath.row]
		let state = toggleState(for: toggle)
		switch state {
		case .none:
			selectedItems.forEach {
				Model.item(uuid: $0)?.labels.append(toggle)
				editedUUIDs.insert($0)
			}
		case .some, .all:
			selectedItems.forEach {
				if let item = Model.item(uuid: $0), let i = item.labels.index(of: toggle) {
					item.labels.remove(at: i)
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

	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			if let t = textField.text, !t.isEmpty {
				textField.text = nil
				textField.resignFirstResponder()
				availableToggles.append(t)
				availableToggles.sort()
				table.reloadData()
				if let i = availableToggles.index(of: t) {
					let ip = IndexPath(row: i, section: 0)
					tableView(table, didSelectRowAt: ip)
					table.scrollToRow(at: ip, at: .middle, animated: true)
				}
			}
			return false
		}
		return true
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		var hadChanges = false
		for uuid in editedUUIDs {
			if let i = Model.item(uuid: uuid) {
				i.markUpdated()
				i.reIndex()
				hadChanges = true
			}
		}
		if hadChanges {
			Model.save()
		}
		endCallback?(hadChanges)
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		headerLabel.alpha = 2.0 - min(2, max(0, scrollView.contentOffset.y / 48.0))
	}
}

