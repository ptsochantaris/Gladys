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

	override func viewDidLoad() {
		super.viewDidLoad()
		var count = 0
		for toggle in Model.labelToggles {
			if toggle.enabled {
				table.selectRow(at: IndexPath(row: count, section: 0), animated: false, scrollPosition: .none)
			}
			count += 1
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
		NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let newState = !Model.labelToggles[indexPath.row].enabled
		Model.labelToggles[indexPath.row].enabled = newState
		if !newState {
			tableView.deselectRow(at: indexPath, animated: false)
		}
		NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
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
		table.layoutIfNeeded()
		preferredContentSize = table.contentSize
	}

	override var preferredContentSize: CGSize {
		didSet {
			navigationController?.preferredContentSize = preferredContentSize
		}
	}
}
