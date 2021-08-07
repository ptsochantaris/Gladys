//
//  LabelSelector.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 14/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelSelector: GladysViewController, UITableViewDelegate, UITableViewDataSource, UISearchControllerDelegate, UISearchResultsUpdating, UITableViewDragDelegate {

	@IBOutlet private var table: UITableView!
	@IBOutlet private var clearAllButton: UIBarButtonItem!
    @IBOutlet private var modeButton: UIBarButtonItem!
    @IBOutlet private var emptyLabel: UILabel!
    @IBOutlet private var closeButton: UIButton!
    
    var filter: Filter!
    
	override func viewDidLoad() {
		super.viewDidLoad()
		doneButtonLocation = .left
        if #available(iOS 15.0, *) {
            table.allowsFocus = true
            table.remembersLastFocusedIndexPath = true
        }
        if filter.rebuildRecentlyAdded() {
            // there were changes to the labels, keep main views in sync
            updates()
        }
		var count = 0
		for toggle in filteredToggles {
			if toggle.active {
				table.selectRow(at: IndexPath(row: count, section: 0), animated: false, scrollPosition: .none)
			}
			count += 1
		}
		clearAllButton.isEnabled = filter.isFilteringLabels
		if filteredToggles.isEmpty {
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
        table.dragInteractionEnabled = true
        table.dragDelegate = self

        updateModeButton()

        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(labelsUpdated), name: .ModelDataUpdated, object: nil)
	}

    @IBAction private func closeSelected(_ sender: UIButton) {
        done()
    }
    
    @objc private func labelsUpdated() {
		table.reloadData()
		clearAllButton.isEnabled = filter.isFilteringLabels
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
		return filteredToggles.isEmpty ? emptyLabel : table
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
        cell.toggle = filteredToggles[indexPath.row]
        cell.parent = self
		return cell
	}

	func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		let toggle = filteredToggles[indexPath.row]
		cell.setSelected(toggle.active, animated: false)
	}
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let toggle = filteredToggles[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            
            var children = [
                UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                    self.rename(toggle: toggle)
                },
                UIAction(title: "Copy to Clipboard", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = toggle.function.displayText
                    genericAlert(title: nil, message: "Copied to clipboard", buttonTitle: nil)
                },
                UIAction(title: "Delete", image: UIImage(systemName: "bin.xmark"), attributes: .destructive) { _ in
                    self.delete(toggle: toggle)
                }
            ]
            
            if UIApplication.shared.supportsMultipleScenes {
                children.insert(UIAction(title: "Open in Window", image: UIImage(systemName: "uiwindow.split.2x1")) { _ in
                    toggle.function.openInWindow(from: self.view.window?.windowScene)
                }, at: 1)
            }
            
            return UIMenu(title: "", image: nil, identifier: nil, options: [], children: children)
        }
    }

	@IBAction private func showAllSelected(_ sender: UIBarButtonItem) {
	    filter.disableAllLabels()
		updates()
		done()
		LabelSelector.filter = ""
	}
    
    @IBAction private func modeSelcted(_ sender: UIBarButtonItem) {
        switch filter.groupingMode {
        case .byLabel:
            filter.groupingMode = .flat
        case .flat:
            filter.groupingMode = .byLabel
        }
        updates() // also causes the user activity to save
        NotificationCenter.default.post(name: .ItemCollectionNeedsDisplay, object: view.window?.windowScene)
        updateModeButton()
    }
    
    private func updateModeButton() {
        modeButton.image = UIImage(systemName: filter.groupingMode.imageName)
    }

	private func updates() {
		NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
		clearAllButton.isEnabled = filter.isFilteringLabels
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		var newState = filteredToggles[indexPath.row]
		newState.active = !newState.active
	    filter.updateLabel(newState)
		if !newState.active {
			tableView.deselectRow(at: indexPath, animated: false)
		}
		updates()
	}
    
	func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
		let toggle = filteredToggles[indexPath.row]
        if case .userLabel = toggle.function {
            return .delete
        } else {
            return .none
        }
	}

    private func rename(toggle: Filter.Toggle) {
        let a = UIAlertController(title: "Rename '\(toggle.function.displayText)'?", message: "This will change it on all items that contain it.", preferredStyle: .alert)
        var textField: UITextField?
        a.addTextField { field in
            field.autocapitalizationType = .sentences
            field.text = toggle.function.displayText
            textField = field
        }
        a.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            if let field = textField, let text = field.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                self?.filter.renameLabel(toggle.function.displayText, to: text)
            }
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if navigationItem.searchController?.isActive ?? false {
            navigationItem.searchController?.present(a, animated: true)
        } else {
            present(a, animated: true)
        }
    }
        
    private func delete(toggle: Filter.Toggle) {
		let a = UIAlertController(title: "Are you sure?", message: "This will remove the label '\(toggle.function.displayText)' from any item that contains it.", preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "Remove From All Items", style: .destructive) { [weak self] _ in
			guard let s = self else { return }
            s.filter.removeLabel(toggle.function.displayText)
            if s.filter.labelToggles.isEmpty {
                s.table.isHidden = true
				s.emptyLabel.isHidden = false
				s.clearAllButton.isEnabled = false
				s.navigationController?.setNavigationBarHidden(true, animated: false)
				UIAccessibility.post(notification: .layoutChanged, argument: s.emptyLabel)
			} else if let i = s.filteredToggles.firstIndex(of: toggle) {
                let indexPath = IndexPath(row: i, section: 0)
                s.table.deleteRows(at: [indexPath], with: .automatic)
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
        
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let toggle = filteredToggles[indexPath.row]
        if let d = toggle.function.dragItem {
            return [d]
        } else {
            return []
        }
    }

	override func done() {
		if let s = navigationItem.searchController, s.isActive {
			s.delegate = nil
			s.searchResultsUpdater = nil
			s.dismiss(animated: false)
		}
		dismiss(animated: true)
	}

	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()
        let fullscreen = (navigationItem.leftBarButtonItems?.count ?? 0) > 1
        view.backgroundColor = fullscreen ? UIColor.systemBackground : .clear
        closeButton.isHidden = !fullscreen
	}

	/////////////// search

	static private var filter = ""

	var filteredToggles: [Filter.Toggle] {
		let items: [Filter.Toggle]
		if LabelSelector.filter.isEmpty {
			items = filter.labelToggles
		} else {
            let function = Filter.Toggle.Function.userLabel(LabelSelector.filter)
			items = filter.labelToggles.filter { $0.function == function }
		}
		return items.filter {
            if case .userLabel = $0.function {
                return true
            }
            return $0.active || $0.count > 0
            
        }
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
