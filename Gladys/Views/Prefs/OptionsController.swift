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
	@IBOutlet private weak var fullScreenSwitch: UISwitch!
    @IBOutlet private weak var fullScreenHolder: SwitchHolder!
    @IBOutlet private weak var displayLabelsInMainViewSwitch: UISwitch!
	@IBOutlet private weak var allowLabelsInExtensionSwitch: UISwitch!
	@IBOutlet private weak var wideModeSwitch: UISwitch!
	@IBOutlet private weak var inclusiveSearchTermsSwitch: UISwitch!
	@IBOutlet private weak var siriSettingsButton: UIBarButtonItem!
    @IBOutlet private weak var autoConvertUrlsSwitch: UISwitch!
    @IBOutlet private weak var blockGladysUrls: UISwitch!
    @IBOutlet private weak var generateLabelsFromTitlesSwitch: UISwitch!
    @IBOutlet private weak var generateLabelsFromThumbnailsSwitch: UISwitch!

	@IBOutlet private weak var actionSelector: UISegmentedControl!
	@IBOutlet private weak var autoArchiveSwitch: UISwitch!
	@IBOutlet private weak var exclusiveLabelsSwitch: UISwitch!
    @IBOutlet private weak var fileMirrorSwitch: UISwitch!
    
	@IBAction private func wideModeSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.wideMode = sender.isOn
        imageCache.removeAllObjects()
        NotificationCenter.default.post(name: .ForceLayoutRequested, object: nil)
        NotificationCenter.default.post(name: .ItemCollectionNeedsDisplay, object: true)
	}

	@IBAction private func inclusiveSearchTermsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.inclusiveSearchTerms = sender.isOn
        view.associatedFilter?.updateFilter(signalUpdate: true)
	}

	@IBAction private func allowLabelsInExtensionSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.setLabelsWhenActioning = sender.isOn
	}

	@IBAction private func displayLabelsInMainViewSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.displayLabelsInMainView = sender.isOn
        NotificationCenter.default.post(name: .ItemCollectionNeedsDisplay, object: true)
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

	@IBAction private func exclusiveMultipleLabelsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.exclusiveMultipleLabels = sender.isOn
        view.associatedFilter?.updateFilter(signalUpdate: true)
	}

	@IBAction private func autoArchiveSwitchSelected(_ sender: UISwitch) {
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

	@IBAction private func actionSelectorValueChanged(_ sender: UISegmentedControl) {
		if let value = DefaultTapAction(rawValue: sender.selectedSegmentIndex) {
			PersistedOptions.actionOnTap = value
		}
	}

	@IBAction private func twoColumnsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.forceTwoColumnPreference = sender.isOn
		if phoneMode {
            NotificationCenter.default.post(name: .ForceLayoutRequested, object: nil)
		}
	}

	@IBAction private func separateItemsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.separateItemPreference = sender.isOn
	}

	@IBAction private func displayNotesInMainViewSelected(_ sender: UISwitch) {
		PersistedOptions.displayNotesInMainView = sender.isOn
        NotificationCenter.default.post(name: .ItemCollectionNeedsDisplay, object: true)
	}

	@IBAction private func fullScreenPreviewsSelected(_ sender: UISwitch) {
		PersistedOptions.fullScreenPreviews = sender.isOn
	}

    @IBAction private func autoConvertUrlsSelected(_ sender: UISwitch) {
        PersistedOptions.automaticallyDetectAndConvertWebLinks = sender.isOn
    }
    
    @IBAction private func blockGladysLinksSelected(_ sender: UISwitch) {
        PersistedOptions.blockGladysUrlRequests = sender.isOn
    }
    
    @IBAction private func generateLabelsFromTitleSelected(_ sender: UISwitch) {
        PersistedOptions.autoGenerateLabelsFromText = sender.isOn
    }

    @IBAction private func generateLabelsFromThumbnailSelected(_ sender: UISwitch) {
        PersistedOptions.autoGenerateLabelsFromImage = sender.isOn
    }

    @IBAction private func fileMirrorSwitch(_ sender: UISwitch) {
        let on = sender.isOn
        PersistedOptions.mirrorFilesToDocuments = on
        sender.isEnabled = false
        if on {
            MirrorManager.startMirrorMonitoring()
            Model.createMirror {
                sender.isEnabled = true
            }
        } else {
            MirrorManager.stopMirrorMonitoring()
            Model.deleteMirror {
                sender.isEnabled = true
            }
        }
    }
    
	override func viewDidLoad() {
		super.viewDidLoad()

		doneButtonLocation = .right

        autoConvertUrlsSwitch.isOn = PersistedOptions.automaticallyDetectAndConvertWebLinks
        blockGladysUrls.isOn = PersistedOptions.blockGladysUrlRequests
        generateLabelsFromTitlesSwitch.isOn = PersistedOptions.autoGenerateLabelsFromText
        generateLabelsFromThumbnailsSwitch.isOn = PersistedOptions.autoGenerateLabelsFromImage
		separateItemsSwitch.isOn = PersistedOptions.separateItemPreference
		twoColumnsSwitch.isOn = PersistedOptions.forceTwoColumnPreference
		removeItemsWhenDraggedOutSwitch.isOn = PersistedOptions.removeItemsWhenDraggedOut
		dontAutoLabelNewItemsSwitch.isOn = PersistedOptions.dontAutoLabelNewItems
		displayNotesInMainViewSwitch.isOn = PersistedOptions.displayNotesInMainView
		displayLabelsInMainViewSwitch.isOn = PersistedOptions.displayLabelsInMainView
		showCopyMoveSwitchSelectorSwitch.isOn = PersistedOptions.showCopyMoveSwitchSelector
		allowLabelsInExtensionSwitch.isOn = PersistedOptions.setLabelsWhenActioning
		inclusiveSearchTermsSwitch.isOn = PersistedOptions.inclusiveSearchTerms
		autoArchiveSwitch.isOn = PersistedOptions.autoArchiveUrlComponents
		exclusiveLabelsSwitch.isOn = PersistedOptions.exclusiveMultipleLabels
        fileMirrorSwitch.isOn = PersistedOptions.mirrorFilesToDocuments
		wideModeSwitch.isOn = PersistedOptions.wideMode
		fullScreenSwitch.isOn = PersistedOptions.fullScreenPreviews
        fullScreenHolder.isHidden = UIDevice.current.userInterfaceIdiom == .phone

		actionSelector.selectedSegmentIndex = PersistedOptions.actionOnTap.rawValue
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		super.prepare(for: segue, sender: sender)
        if segue.identifier == "toSiriOptions", let p = segue.destination.popoverPresentationController {
            p.backgroundColor = .white
            p.delegate = self
        }
	}

	func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
		return .none
	}
}
