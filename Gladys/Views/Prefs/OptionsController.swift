//
//  OptionsController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 04/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class OptionsController: GladysViewController {

	@IBOutlet private weak var separateItemsSwitch: UISwitch!
	@IBOutlet private weak var twoColumnsSwitch: UISwitch!
	@IBOutlet private weak var removeItemsWhenDraggedOutSwitch: UISwitch!
	@IBOutlet private weak var dontAutoLabelNewItemsSwitch: UISwitch!
	@IBOutlet private weak var displayNotesInMainViewSwitch: UISwitch!
	@IBOutlet private weak var showCopyMoveSwitchSelectorSwitch: UISwitch!
	@IBOutlet private weak var darkModeSwitch: UISwitch!
	@IBOutlet private weak var fullScreenSwitch: UISwitch!
	@IBOutlet private weak var mergeSwitch: UISwitch!
	@IBOutlet private weak var displayLabelsInMainViewSwitch: UISwitch!

	@IBOutlet private var headerLabels: [UILabel]!
	@IBOutlet private var subtitleLabels: [UILabel]!

	@IBAction private func displayLabelsInMainViewSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.displayLabelsInMainView = sender.isOn
		ViewController.shared.reloadData()
	}

	@IBAction private func showCopyMoveSwitchSelectorSwitchChanged(_ sender: UISwitch) {
		PersistedOptions.showCopyMoveSwitchSelector = sender.isOn
	}

	@IBAction private func removeItemsWhenDraggedOutChanged(_ sender: UISwitch) {
		PersistedOptions.removeItemsWhenDraggedOut = sender.isOn
	}

	@IBAction private func dontAutoLabelNewItemsChanged(_ sender: UISwitch) {
		PersistedOptions.dontAutoLabelNewItems = sender.isOn
	}

	@IBAction private func twoColumnsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.forceTwoColumnPreference = sender.isOn
		if ViewController.shared.phoneMode {
			ViewController.shared.forceLayout()
		}
	}

	@IBAction private func separateItemsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.separateItemPreference = sender.isOn
	}

	@IBAction private func displayNotesInMainViewSelected(_ sender: UISwitch) {
		PersistedOptions.displayNotesInMainView = sender.isOn
		ViewController.shared.reloadData()
	}

	@IBAction private func darkModeSelected(_ sender: UISwitch) {
		PersistedOptions.darkMode = sender.isOn
		NotificationCenter.default.post(name: .DarkModeChanged, object: nil)
	}

	@IBAction private func fullScreenPreviewsSelected(_ sender: UISwitch) {
		PersistedOptions.fullScreenPreviews = sender.isOn
	}

	@IBAction private func mergeSwitchSelected(_ sender: UISwitch) {
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
