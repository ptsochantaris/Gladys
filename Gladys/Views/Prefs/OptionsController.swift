//
//  OptionsController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 04/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class OptionsController: GladysViewController {

	@IBOutlet weak var separateItemsSwitch: UISwitch!
	@IBOutlet weak var twoColumnsSwitch: UISwitch!
	@IBOutlet weak var removeItemsWhenDraggedOutSwitch: UISwitch!
	@IBOutlet weak var dontAutoLabelNewItemsSwitch: UISwitch!
	@IBOutlet weak var displayNotesInMainViewSwitch: UISwitch!
	@IBOutlet weak var showCopyMoveSwitchSelectorSwitch: UISwitch!
	@IBOutlet weak var darkModeSwitch: UISwitch!
	@IBOutlet weak var fullScreenSwitch: UISwitch!
	@IBOutlet weak var mergeSwitch: UISwitch!
	@IBOutlet weak var displayLabelsInMainViewSwitch: UISwitch!

	@IBOutlet var headerLabels: [UILabel]!
	@IBOutlet var subtitleLabels: [UILabel]!

	@IBAction func displayLabelsInMainViewSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.displayLabelsInMainView = sender.isOn
		ViewController.shared.reloadData()
	}

	@IBAction func showCopyMoveSwitchSelectorSwitchChanged(_ sender: UISwitch) {
		PersistedOptions.showCopyMoveSwitchSelector = sender.isOn
	}

	@IBAction func removeItemsWhenDraggedOutChanged(_ sender: UISwitch) {
		PersistedOptions.removeItemsWhenDraggedOut = sender.isOn
	}

	@IBAction func dontAutoLabelNewItemsChanged(_ sender: UISwitch) {
		PersistedOptions.dontAutoLabelNewItems = sender.isOn
	}

	@IBAction func twoColumnsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.forceTwoColumnPreference = sender.isOn
		if ViewController.shared.phoneMode {
			ViewController.shared.forceLayout()
		}
	}

	@IBAction func separateItemsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.separateItemPreference = sender.isOn
	}

	@IBAction func displayNotesInMainViewSelected(_ sender: UISwitch) {
		PersistedOptions.displayNotesInMainView = sender.isOn
		ViewController.shared.reloadData()
	}

	@IBAction func darkModeSelected(_ sender: UISwitch) {
		PersistedOptions.darkMode = sender.isOn
		NotificationCenter.default.post(name: .DarkModeChanged, object: nil)
	}

	@IBAction func fullScreenPreviewsSelected(_ sender: UISwitch) {
		PersistedOptions.fullScreenPreviews = sender.isOn
	}

	@IBAction func mergeSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.allowMergeOfTypeItems = sender.isOn
	}

	override func darkModeChanged() {
		super.darkModeChanged()
		separateItemsSwitch.onTintColor = view.tintColor
		twoColumnsSwitch.onTintColor = view.tintColor
		removeItemsWhenDraggedOutSwitch.onTintColor = view.tintColor
		dontAutoLabelNewItemsSwitch.onTintColor = view.tintColor
		displayNotesInMainViewSwitch.onTintColor = view.tintColor
		displayLabelsInMainViewSwitch.onTintColor = view.tintColor
		showCopyMoveSwitchSelectorSwitch.onTintColor = view.tintColor
		darkModeSwitch.onTintColor = view.tintColor
		fullScreenSwitch.onTintColor = view.tintColor
		mergeSwitch.onTintColor = view.tintColor
		if PersistedOptions.darkMode {
			for l in headerLabels {
				l.textColor = UIColor.lightGray
			}
			for s in subtitleLabels {
				s.textColor = UIColor.gray
			}
		} else {
			for l in headerLabels {
				l.textColor = UIColor.darkGray
			}
			for s in subtitleLabels {
				s.textColor = UIColor.gray
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		doneLocation = .right

		separateItemsSwitch.tintColor = .lightGray
		separateItemsSwitch.isOn = PersistedOptions.separateItemPreference

		twoColumnsSwitch.tintColor = .lightGray
		twoColumnsSwitch.isOn = PersistedOptions.forceTwoColumnPreference

		removeItemsWhenDraggedOutSwitch.tintColor = .lightGray
		removeItemsWhenDraggedOutSwitch.isOn = PersistedOptions.removeItemsWhenDraggedOut

		dontAutoLabelNewItemsSwitch.tintColor = .lightGray
		dontAutoLabelNewItemsSwitch.isOn = PersistedOptions.dontAutoLabelNewItems

		displayNotesInMainViewSwitch.tintColor = .lightGray
		displayNotesInMainViewSwitch.isOn = PersistedOptions.displayNotesInMainView

		displayLabelsInMainViewSwitch.tintColor = .lightGray
		displayLabelsInMainViewSwitch.isOn = PersistedOptions.displayLabelsInMainView

		showCopyMoveSwitchSelectorSwitch.tintColor = .lightGray
		showCopyMoveSwitchSelectorSwitch.isOn = PersistedOptions.showCopyMoveSwitchSelector

		darkModeSwitch.tintColor = .lightGray
		darkModeSwitch.isOn = PersistedOptions.darkMode

		fullScreenSwitch.tintColor = .lightGray
		fullScreenSwitch.isOn = PersistedOptions.fullScreenPreviews

		mergeSwitch.tintColor = .lightGray
		mergeSwitch.isOn = PersistedOptions.allowMergeOfTypeItems

		darkModeChanged()
	}
}
