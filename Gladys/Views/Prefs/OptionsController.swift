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

	override func viewDidLoad() {
		super.viewDidLoad()

		doneLocation = .right

		separateItemsSwitch.tintColor = UIColor.lightGray
		separateItemsSwitch.onTintColor = view.tintColor
		separateItemsSwitch.isOn = PersistedOptions.separateItemPreference

		twoColumnsSwitch.tintColor = UIColor.lightGray
		twoColumnsSwitch.onTintColor = view.tintColor
		twoColumnsSwitch.isOn = PersistedOptions.forceTwoColumnPreference

		removeItemsWhenDraggedOutSwitch.tintColor = UIColor.lightGray
		removeItemsWhenDraggedOutSwitch.onTintColor = view.tintColor
		removeItemsWhenDraggedOutSwitch.isOn = PersistedOptions.removeItemsWhenDraggedOut

		dontAutoLabelNewItemsSwitch.tintColor = UIColor.lightGray
		dontAutoLabelNewItemsSwitch.onTintColor = view.tintColor
		dontAutoLabelNewItemsSwitch.isOn = PersistedOptions.dontAutoLabelNewItems

		displayNotesInMainViewSwitch.tintColor = UIColor.lightGray
		displayNotesInMainViewSwitch.onTintColor = view.tintColor
		displayNotesInMainViewSwitch.isOn = PersistedOptions.displayNotesInMainView

		showCopyMoveSwitchSelectorSwitch.tintColor = UIColor.lightGray
		showCopyMoveSwitchSelectorSwitch.onTintColor = view.tintColor
		showCopyMoveSwitchSelectorSwitch.isOn = PersistedOptions.showCopyMoveSwitchSelector
	}
}
