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
	@IBOutlet weak var deleteAllButton: NSButton!

	override func viewDidLoad() {
		super.viewDidLoad()

		NotificationCenter.default.addObserver(forName: .CloudManagerStatusChanged, object: nil, queue: OperationQueue.main) { [weak self] n in
			self?.updateSyncSwitches()
		}
		updateSyncSwitches()
	}

	private func updateSyncSwitches() {
		syncSwitch.integerValue = CloudManager.syncSwitchedOn ? 1 : 0

		if CloudManager.syncTransitioning || CloudManager.syncing {
			syncSwitch.isEnabled = false
			syncSwitch.title = CloudManager.syncString
			syncSpinner.startAnimation(nil)
			deleteAllButton.isEnabled = false
		} else {
			syncSwitch.isEnabled = true
			syncSwitch.title = "iCloud Sync"
			syncSpinner.stopAnimation(nil)
			deleteAllButton.isEnabled = true
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
