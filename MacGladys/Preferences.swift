//
//  Preferences.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 29/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa

final class Preferences: NSViewController {
	@IBOutlet weak var syncSwitch: NSButton!
	@IBOutlet weak var syncSpinner: NSProgressIndicator!
	@IBOutlet weak var syncNowButton: NSButton!

	@IBOutlet weak var deleteAllButton: NSButton!

	@IBOutlet weak var displayNotesSwitch: NSButton!
	@IBOutlet weak var separateItemsSwitch: NSButton!
	@IBOutlet weak var moveSwitch: NSButton!
	@IBOutlet weak var autoLabelSwitch: NSButton!
	@IBOutlet weak var autoMergingSwitch: NSButton!

	override func viewDidLoad() {
		super.viewDidLoad()

		displayNotesSwitch.integerValue = PersistedOptions.displayNotesInMainView ? 1 : 0
		separateItemsSwitch.integerValue = PersistedOptions.separateItemPreference ? 1 : 0
		moveSwitch.integerValue = PersistedOptions.removeItemsWhenDraggedOut ? 1 : 0
		autoLabelSwitch.integerValue = PersistedOptions.dontAutoLabelNewItems ? 1 : 0
		autoMergingSwitch.integerValue = PersistedOptions.allowMergeOfTypeItems ? 1 : 0

		NotificationCenter.default.addObserver(forName: .CloudManagerStatusChanged, object: nil, queue: OperationQueue.main) { [weak self] n in
			self?.updateSyncSwitches()
		}
		updateSyncSwitches()
	}

	private func updateSyncSwitches() {
		syncSwitch.integerValue = CloudManager.syncSwitchedOn ? 1 : 0

		if CloudManager.syncTransitioning || CloudManager.syncing {
			syncSwitch.isEnabled = false
			syncNowButton.isEnabled = false
			deleteAllButton.isEnabled = false
			syncSwitch.title = CloudManager.syncString
			syncSpinner.startAnimation(nil)
		} else {
			syncSwitch.isEnabled = true
			syncNowButton.isEnabled = CloudManager.syncSwitchedOn
			deleteAllButton.isEnabled = true
			syncSwitch.title = "iCloud Sync"
			syncSpinner.stopAnimation(nil)
		}
	}

	@IBAction func deleteLocalItemsSelected(_ sender: NSButton) {

		let title: String
		let subtitle: String
		let actionName: String

		if CloudManager.syncSwitchedOn {
			title = "Remove from all devices?"
			subtitle = "Sync is switched on, so this action will remove your entire collection from all synced devices. This cannot be undone."
			actionName = "Delete From All Devices"
		} else {
			title = "Are you sure?"
			subtitle = "This will remove all items from your collection. This cannot be undone."
			actionName = "Delete All"
		}

		let a = NSAlert()
		a.messageText = title
		a.informativeText = subtitle
		a.addButton(withTitle: actionName)
		a.addButton(withTitle: "Cancel")

		a.beginSheetModal(for: view.window!) { response in
			if response == .alertFirstButtonReturn {
				Model.resetEverything()
			}
		}
	}

	@IBAction func displayNotesSwitchSelected(_ sender: NSButton) {
		PersistedOptions.displayNotesInMainView = sender.integerValue == 1
		ViewController.shared.reloadData()
	}

	@IBAction func multipleSwitchChanged(_ sender: NSButton) {
		PersistedOptions.separateItemPreference = sender.integerValue == 1
	}

	@IBAction func moveSwitchChanged(_ sender: NSButton) {
		PersistedOptions.removeItemsWhenDraggedOut = sender.integerValue == 1
	}

	@IBAction func autoLabelSwitchChanged(_ sender: NSButton) {
		PersistedOptions.dontAutoLabelNewItems = sender.integerValue == 1
	}

	@IBAction func mergingSwitchSelected(_ sender: NSButton) {
		PersistedOptions.allowMergeOfTypeItems = sender.integerValue == 1
	}

	@IBAction func syncSwitchChanged(_ sender: NSButton) {
		syncSwitch.isEnabled = false

		if CloudManager.syncSwitchedOn {
			CloudManager.deactivate(force: false) { error in
				DispatchQueue.main.async {
					if let error = error {
						genericAlert(title: "Could not change state", message: error.finalDescription)
					}
				}
			}
		} else {
			CloudManager.activate { error in
				DispatchQueue.main.async {
					if let error = error {
						genericAlert(title: "Could not change state", message: error.finalDescription)
					}
				}
			}
		}
	}
}
