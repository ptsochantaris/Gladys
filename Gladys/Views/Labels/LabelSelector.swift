//
//  LabelSelector.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 14/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelSelector: GladysViewController, UITableViewDelegate, UITableViewDataSource, UISearchControllerDelegate, UISearchResultsUpdating {

	@IBOutlet private weak var table: UITableView!
	@IBOutlet private var clearAllButton: UIBarButtonItem!
	@IBOutlet private weak var emptyLabel: UILabel!

	override func viewDidLoad() {
		super.viewDidLoad()
		doneLocation = .left
		var count = 0
		for toggle in filteredToggles {
			if toggle.enabled {
				table.selectRow(at: IndexPath(row: count, section: 0), animated: false, scrollPosition: .none)
			}
			count += 1
		}
		clearAllButton.isEnabled = Model.isFilteringLabels
		if filteredToggles.count == 0 {
			table.isHidden = true
			navigationController?.setNavigationBarHidden(true, animated: false)

		} else {
			emptyLabel.isHidden = true

			let searchController = UISearchController(searchResultsController: nil)
			searchController.obscuresBackgroundDuringPresentation = false
			searchController.obscuresBackgroundDuringPresentation = false
			searchController.delegate = self
			searchController.searchResultsUpdater = self
			searchController.searchBar.tintColor = view.tintColor
			searchController.hidesNavigationBarDuringPresentation = false
			navigationItem.hidesSearchBarWhenScrolling = false
			navigationItem.searchController = searchController

            if let t = searchController.searchBar.subviews.first?.subviews.first(where: { $0 is UITextField }) as? UITextField {
                DispatchQueue.main.async {
                    t.textColor = .darkText
                }
            }
		}

		table.tableFooterView = UIView()

		NotificationCenter.default.addObserver(self, selector: #selector(labelsUpdated), name: .ExternalDataUpdated, object: nil)
	}

	@objc private func labelsUpdated() {
		table.reloadData()
		clearAllButton.isEnabled = Model.isFilteringLabels
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if !LabelSelector.filter.isEmpty {
			navigationItem.searchController?.searchBar.text = LabelSelector.filter
			navigationItem.searchController?.isActive = true
		}
		sizeWindow()
	}

	override var initialAccessibilityElement: UIView {
		return filteredToggles.count == 0 ? emptyLabel : table
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		sizeWindow()
	}

	private func sizeWindow() {
		if table.isHidden {
			preferredContentSize = CGSize(width: 240, height: 240)
		} else {
			let full = table.contentSize.height + 8
			preferredContentSize = CGSize(width: 240, height: full)
		}
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

	@IBAction private func clearAllSelected(_ sender: UIBarButtonItem) {
	    Model.disableAllLabels()
		updates()
		done()
		LabelSelector.filter = ""
	}

	private func updates() {
		NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
		clearAllButton.isEnabled = Model.isFilteringLabels
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		var newState = filteredToggles[indexPath.row]
		newState.enabled = !newState.enabled
	    Model.updateLabel(newState)
		if !newState.enabled {
			tableView.deselectRow(at: indexPath, animated: false)
		}
		updates()
	}

	func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
		let toggle = filteredToggles[indexPath.row]
		return toggle.emptyChecker ? .none : .delete
	}

	func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
		let toggle = filteredToggles[indexPath.row]
		let a = UIAlertController(title: "Are you sure?", message: "This will remove the label '\(toggle.name)' from any item that contains it.", preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "Remove From All Items", style: .destructive) { [weak self] action in
			guard let s = self else { return }
		    Model.removeLabel(toggle.name)
			if Model.labelToggles.count == 0 {
				tableView.isHidden = true
				s.emptyLabel.isHidden = false
				s.clearAllButton.isEnabled = false
				s.navigationController?.setNavigationBarHidden(true, animated: false)
				UIAccessibility.post(notification: .layoutChanged, argument: s.emptyLabel)
			} else {
				tableView.deleteRows(at: [indexPath], with: .automatic)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				s.sizeWindow()
			}
		})
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
		if navigationItem.searchController?.isActive ?? false {
			navigationItem.searchController?.present(a, animated: true)
		} else {
			present(a, animated: true)
		}
	}

	override func done() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
		}
		if navigationItem.searchController?.isActive ?? false {
			navigationItem.searchController?.delegate = nil
			navigationItem.searchController?.searchResultsUpdater = nil
			navigationItem.searchController?.dismiss(animated: false)
		}
		dismiss(animated: true)
	}

	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()
		view.backgroundColor = navigationItem.leftBarButtonItem != nil ? .white : .clear
	}

	/////////////// search

	static private var filter = ""

	var filteredToggles: [Model.LabelToggle] {
		let items: [Model.LabelToggle]
		if LabelSelector.filter.isEmpty {
			items = Model.labelToggles
		} else {
			items = Model.labelToggles.filter { $0.name.localizedCaseInsensitiveContains(LabelSelector.filter) }
		}
		return items.filter { !$0.emptyChecker || $0.enabled || $0.count > 0 }
	}

	func willDismissSearchController(_ searchController: UISearchController) {
		LabelSelector.filter = ""
		table.reloadData()
	}

	func didDismissSearchController(_ searchController: UISearchController) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			self.sizeWindow()
		}
	}

	func updateSearchResults(for searchController: UISearchController) {
		LabelSelector.filter = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		table.reloadData()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			self.sizeWindow()
		}
	}
}
