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

	override func darkModeChanged() {
		super.darkModeChanged()
		separateItemsSwitch.onTintColor = view.tintColor
		twoColumnsSwitch.onTintColor = view.tintColor
		removeItemsWhenDraggedOutSwitch.onTintColor = view.tintColor
		dontAutoLabelNewItemsSwitch.onTintColor = view.tintColor
		displayNotesInMainViewSwitch.onTintColor = view.tintColor
		showCopyMoveSwitchSelectorSwitch.onTintColor = view.tintColor
		darkModeSwitch.onTintColor = view.tintColor
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		doneLocation = .right

		separateItemsSwitch.tintColor = UIColor.lightGray
		separateItemsSwitch.isOn = PersistedOptions.separateItemPreference

		twoColumnsSwitch.tintColor = UIColor.lightGray
		twoColumnsSwitch.isOn = PersistedOptions.forceTwoColumnPreference

		removeItemsWhenDraggedOutSwitch.tintColor = UIColor.lightGray
		removeItemsWhenDraggedOutSwitch.isOn = PersistedOptions.removeItemsWhenDraggedOut

		dontAutoLabelNewItemsSwitch.tintColor = UIColor.lightGray
		dontAutoLabelNewItemsSwitch.isOn = PersistedOptions.dontAutoLabelNewItems

		displayNotesInMainViewSwitch.tintColor = UIColor.lightGray
		displayNotesInMainViewSwitch.isOn = PersistedOptions.displayNotesInMainView

		showCopyMoveSwitchSelectorSwitch.tintColor = UIColor.lightGray
		showCopyMoveSwitchSelectorSwitch.isOn = PersistedOptions.showCopyMoveSwitchSelector

		darkModeSwitch.tintColor = UIColor.lightGray
		darkModeSwitch.isOn = PersistedOptions.darkMode

		darkModeChanged()
	}
}
