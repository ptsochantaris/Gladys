//
//  OptionsController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 04/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class OptionsController: GladysViewController, UIPopoverPresentationControllerDelegate {

	@IBOutlet private weak var twoColumnsSwitch: UISwitch!
	@IBOutlet private weak var separateItemsSwitch: UISwitch!
	@IBOutlet private weak var removeItemsWhenDraggedOutSwitch: UISwitch!
	@IBOutlet private weak var dontAutoLabelNewItemsSwitch: UISwitch!
	@IBOutlet private weak var displayNotesInMainViewSwitch: UISwitch!
	@IBOutlet private weak var showCopyMoveSwitchSelectorSwitch: UISwitch!
	@IBOutlet private weak var darkModeSwitch: UISwitch!
	@IBOutlet private weak var fullScreenSwitch: UISwitch!
	@IBOutlet private weak var displayLabelsInMainViewSwitch: UISwitch!
	@IBOutlet private weak var allowLabelsInExtensionSwitch: UISwitch!
	@IBOutlet private weak var wideModeSwitch: UISwitch!
	@IBOutlet private weak var inclusiveSearchTermsSwitch: UISwitch!
	@IBOutlet private weak var siriSettingsButton: UIBarButtonItem!
    @IBOutlet private weak var autoConvertUrlsSwitch: UISwitch!
    @IBOutlet private weak var blockGladysUrls: UISwitch!

	@IBOutlet private weak var actionSelector: UISegmentedControl!
	@IBOutlet private weak var autoArchiveSwitch: UISwitch!
	@IBOutlet private weak var exclusiveLabelsSwitch: UISwitch!

	@IBOutlet private var headerLabels: [UILabel]!
	@IBOutlet private var subtitleLabels: [UILabel]!
	@IBOutlet private var titleLabels: [UILabel]!

	@IBAction private func wideModeSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.wideMode = sender.isOn
		clearCaches()
		ViewController.shared.forceLayout()
		ViewController.shared.reloadData(onlyIfPopulated: true)
	}

	@IBAction private func inclusiveSearchTermsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.inclusiveSearchTerms = sender.isOn
		ViewController.shared.reloadData(onlyIfPopulated: true)
	}

	@IBAction private func allowLabelsInExtensionSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.setLabelsWhenActioning = sender.isOn
	}

	@IBAction private func displayLabelsInMainViewSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.displayLabelsInMainView = sender.isOn
		ViewController.shared.reloadData(onlyIfPopulated: true)
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

	@IBAction func exclusiveMultipleLabelsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.exclusiveMultipleLabels = sender.isOn
		NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil, userInfo: nil)
	}

	@IBAction func autoArchiveSwitchSelected(_ sender: UISwitch) {
		if sender.isOn {
			let a = UIAlertController(title: "Are you sure?", message: "This can use a lot of data (and storage) when adding web links!\n\nActivate this only if you know what you are doing.", preferredStyle: .alert)
			a.addAction(UIAlertAction(title: "Activate", style: .destructive) { _ in
				PersistedOptions.autoArchiveUrlComponents = true
			})
			a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak sender] _ in
				sender?.setOn(false, animated: true)
			})
			present(a, animated: true)
		} else {
			PersistedOptions.autoArchiveUrlComponents = false
		}
	}

	@IBAction func actionSelectorValueChanged(_ sender: UISegmentedControl) {
		if let value = DefaultTapAction(rawValue: sender.selectedSegmentIndex) {
			PersistedOptions.actionOnTap = value
		}
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
		ViewController.shared.reloadData(onlyIfPopulated: true)
	}

	@IBAction private func darkModeSelected(_ sender: UISwitch) {
		PersistedOptions.darkMode = sender.isOn
		NotificationCenter.default.post(name: .DarkModeChanged, object: nil)
	}

	@IBAction private func fullScreenPreviewsSelected(_ sender: UISwitch) {
		PersistedOptions.fullScreenPreviews = sender.isOn
	}

    @IBAction private func autoConvertUrlsSelected(_ sender: UISwitch) {
        PersistedOptions.automaticallyDetectAndConvertWebLinks = sender.isOn
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
		allowLabelsInExtensionSwitch.onTintColor = view.tintColor
		wideModeSwitch.onTintColor = view.tintColor
		autoArchiveSwitch.onTintColor = view.tintColor
		exclusiveLabelsSwitch.onTintColor = view.tintColor
		inclusiveSearchTermsSwitch.onTintColor = view.tintColor
        autoConvertUrlsSwitch.onTintColor = view.tintColor
        blockGladysUrls.onTintColor = view.tintColor

        subtitleLabels.forEach { $0.textColor = UIColor.gray }
		titleLabels.forEach { $0.textColor = ViewController.tintColor }
		if PersistedOptions.darkMode {
			headerLabels.forEach { $0.textColor = UIColor.lightGray }
		} else {
			headerLabels.forEach { $0.textColor = UIColor.darkGray }
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		if #available(iOS 12.0, *) {
			siriSettingsButton.isEnabled = true
		} else {
			siriSettingsButton.isEnabled = false
		}

		doneLocation = .right

        autoConvertUrlsSwitch.tintColor = .lightGray
        autoConvertUrlsSwitch.isOn = PersistedOptions.automaticallyDetectAndConvertWebLinks
        
        blockGladysUrls.tintColor = .lightGray
        blockGladysUrls.isOn = PersistedOptions.blockGladysUrlRequests
        
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

		allowLabelsInExtensionSwitch.tintColor = .lightGray
		allowLabelsInExtensionSwitch.isOn = PersistedOptions.setLabelsWhenActioning

		inclusiveSearchTermsSwitch.tintColor = .lightGray
		inclusiveSearchTermsSwitch.isOn = PersistedOptions.inclusiveSearchTerms

		autoArchiveSwitch.tintColor = .lightGray
		autoArchiveSwitch.isOn = PersistedOptions.autoArchiveUrlComponents

		exclusiveLabelsSwitch.tintColor = .lightGray
		exclusiveLabelsSwitch.isOn = PersistedOptions.exclusiveMultipleLabels

		darkModeSwitch.tintColor = .lightGray
		darkModeSwitch.isOn = PersistedOptions.darkMode

		wideModeSwitch.tintColor = .lightGray
		wideModeSwitch.isOn = PersistedOptions.wideMode

		fullScreenSwitch.tintColor = .lightGray
		fullScreenSwitch.isOn = PersistedOptions.fullScreenPreviews

		actionSelector.selectedSegmentIndex = PersistedOptions.actionOnTap.rawValue

		darkModeChanged()
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
		if #available(iOS 12.0, *) {
			if segue.identifier == "toSiriOptions", let p = segue.destination.popoverPresentationController {
				if PersistedOptions.darkMode {
					p.backgroundColor = .darkGray
				} else {
					p.backgroundColor = .white
				}
				p.delegate = self
			}
		}
	}

	func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
		return .none
	}
}
