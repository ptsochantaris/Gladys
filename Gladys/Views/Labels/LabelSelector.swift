//
//  LabelSelector.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 14/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelSelector: UIViewController, UITableViewDelegate, UITableViewDataSource {

	@IBOutlet weak var table: UITableView!
	@IBOutlet var clearAllButton: UIBarButtonItem!
	@IBOutlet weak var emptyLabel: UILabel!

	override func viewDidLoad() {
		super.viewDidLoad()
		var count = 0
		var enabled = false
		for toggle in Model.labelToggles {
			if toggle.enabled {
				enabled = true
				table.selectRow(at: IndexPath(row: count, section: 0), animated: false, scrollPosition: .none)
			}
			count += 1
		}
		clearAllButton.isEnabled = enabled
		if Model.labelToggles.count == 0 {
			table.isHidden = true
		} else {
			emptyLabel.isHidden = true
		}
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return Model.labelToggles.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "LabelToggleCell") as! LabelToggleCell
		let toggle = Model.labelToggles[indexPath.row]
		cell.labelName.text = toggle.name
		let c = toggle.count
		if c == 1 {
			cell.labelCount.text = "1 item"
		} else {
			cell.labelCount.text = "\(c) items"
		}
		return cell
	}

	@IBAction func clearAllSelected(_ sender: UIBarButtonItem) {
		ViewController.shared.model.disableAllLabels()
		for i in table.indexPathsForSelectedRows ?? [] {
			table.deselectRow(at: i, animated: false)
		}
		updates()
		done()
	}

	private func updates() {
		NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
		clearAllButton.isEnabled = ViewController.shared.model.isFilteringLabels
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let newState = !Model.labelToggles[indexPath.row].enabled
		Model.labelToggles[indexPath.row].enabled = newState
		if !newState {
			tableView.deselectRow(at: indexPath, animated: false)
		}
		updates()
	}

	func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
		return .delete
	}

	func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
		let a = UIAlertController(title: "Are you sure?", message: "This will remove the label from any item that contains it.", preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "Remove From All Items", style: .destructive, handler: { [weak self] action in
			let toggle = Model.labelToggles[indexPath.row]
			ViewController.shared.model.removeLabel(toggle.name)
			tableView.deleteRows(at: [indexPath], with: .automatic)
			if tableView.numberOfRows(inSection: 0) == 0 {
				tableView.isHidden = true
				self?.emptyLabel.isHidden = false
			}
			self?.sizeWindow()
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
		present(a, animated: true)
	}

	@IBAction func doneSelected(_ sender: UIBarButtonItem) {
		done()
	}

	private func done() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
		}
		dismiss(animated: true)
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		sizeWindow()
	}

	private func sizeWindow() {
		if table.numberOfRows(inSection: 0) > 0 {
			table.layoutIfNeeded()
			preferredContentSize = table.contentSize
		} else {
			preferredContentSize = CGSize(width: 240, height: 240)
		}
	}

	override var preferredContentSize: CGSize {
		didSet {
			navigationController?.preferredContentSize = preferredContentSize
		}
	}

	func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
		return .none
	}
}
