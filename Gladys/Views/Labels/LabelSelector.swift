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

	struct LabelToggle {
		let name: String
		let count: Int
		var enabled: Bool
	}

	static var toggles = [LabelToggle]()

	override func viewDidLoad() {
		super.viewDidLoad()
		rebuildLabels()
	}

	private func rebuildLabels() {
		var counts = [String:Int]()
		for item in ViewController.shared.model.drops {
			item.labels.forEach {
				if let c = counts[$0] {
					counts[$0] = c+1
				} else {
					counts[$0] = 1
				}
			}
		}

		let previous = LabelSelector.toggles
		LabelSelector.toggles.removeAll()
		for (label, count) in counts {
			let previousEnabled = (previous.first { $0.enabled == true && $0.name == label } != nil)
			let toggle = LabelToggle(name: label, count: count, enabled: previousEnabled)
			LabelSelector.toggles.append(toggle)
		}
		LabelSelector.toggles.sort { $0.name < $1.name }
		table.reloadData()
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return LabelSelector.toggles.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "LabelToggleCell") as! LabelToggleCell
		let toggle = LabelSelector.toggles[indexPath.row]
		cell.labelName.text = toggle.name
		let c = toggle.count
		if c == 1 {
			cell.labelCount.text = "1 item"
		} else {
			cell.labelCount.text = "\(c) items"
		}
		return cell
	}

	func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		let toggle = LabelSelector.toggles[indexPath.row]
		cell.setSelected(toggle.enabled, animated: false)
	}

	@IBAction func clearAllSelected(_ sender: UIBarButtonItem) {
		for i in table.indexPathsForSelectedRows ?? [] {
			table.deselectRow(at: i, animated: false)
			LabelSelector.toggles[i.row].enabled = false
		}
		NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let newState = !LabelSelector.toggles[indexPath.row].enabled
		LabelSelector.toggles[indexPath.row].enabled = newState
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
