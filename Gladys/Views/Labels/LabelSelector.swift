//
//  LabelSelector.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 14/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelSelector: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchControllerDelegate, UISearchResultsUpdating {

	@IBOutlet weak var table: UITableView!
	@IBOutlet var clearAllButton: UIBarButtonItem!
	@IBOutlet weak var emptyLabel: UILabel!

	override func viewDidLoad() {
		super.viewDidLoad()
		var count = 0
		var enabled = false
		for toggle in filteredToggles {
			if toggle.enabled {
				enabled = true
				table.selectRow(at: IndexPath(row: count, section: 0), animated: false, scrollPosition: .none)
			}
			count += 1
		}
		clearAllButton.isEnabled = enabled
		if filteredToggles.count == 0 {
			table.isHidden = true
		} else {
			emptyLabel.isHidden = true
		}

		table.tableFooterView = UIView()

		let searchController = UISearchController(searchResultsController: nil)
		searchController.dimsBackgroundDuringPresentation = false
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.delegate = self
		searchController.searchResultsUpdater = self
		searchController.searchBar.tintColor = view.tintColor
		searchController.hidesNavigationBarDuringPresentation = false
		navigationItem.searchController = searchController

		layoutTimer = PopTimer(timeInterval: 1) { [weak self] in
			self?.sizeWindow()
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if !LabelSelector.filter.isEmpty {
			navigationItem.searchController?.searchBar.text = LabelSelector.filter
			navigationItem.searchController?.isActive = true
			view.layoutIfNeeded()
		}
		table.layoutIfNeeded()
		sizeWindow()
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return filteredToggles.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "LabelToggleCell") as! LabelToggleCell
		let toggle = filteredToggles[indexPath.row]
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
		let toggle = filteredToggles[indexPath.row]
		cell.setSelected(toggle.enabled, animated: false)
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
		var newState = filteredToggles[indexPath.row]
		newState.enabled = !newState.enabled
		ViewController.shared.model.updateLabel(newState)
		if !newState.enabled {
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
			guard let s = self else { return }
			let toggle = s.filteredToggles[indexPath.row]
			ViewController.shared.model.removeLabel(toggle.name)
			tableView.deleteRows(at: [indexPath], with: .automatic)
			if tableView.numberOfRows(inSection: 0) == 0 {
				tableView.isHidden = true
				self?.emptyLabel.isHidden = false
			}
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

	private var layoutTimer: PopTimer!

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		layoutTimer.push()
	}

	private func sizeWindow() {
		if table.numberOfRows(inSection: 0) > 0 {
			let full = table.contentSize.height
			log("H: \(full)")
			preferredContentSize = CGSize(width: 240, height: full)
		} else {
			preferredContentSize = CGSize(width: 240, height: 240)
		}
	}

	override var preferredContentSize: CGSize {
		didSet {
			navigationController?.preferredContentSize = preferredContentSize
		}
	}

	/////////////// search

	static private var filter = ""

	var filteredToggles: [Model.LabelToggle] {
		if LabelSelector.filter.isEmpty {
			return Model.labelToggles
		} else {
			return Model.labelToggles.filter { $0.name.localizedCaseInsensitiveContains(LabelSelector.filter) }
		}
	}

	func willDismissSearchController(_ searchController: UISearchController) {
		LabelSelector.filter = ""
		table.reloadData()
		layoutTimer.push()
	}

	func updateSearchResults(for searchController: UISearchController) {
		LabelSelector.filter = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		table.reloadData()
		layoutTimer.push()
	}
}
