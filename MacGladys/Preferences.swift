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
	@IBOutlet weak var doneButton: NSButton!
	@IBOutlet weak var eraseAlliCloudDataButton: NSButton!

	@IBOutlet weak var displayNotesSwitch: NSButton!
	@IBOutlet weak var displayLabelsSwitch: NSButton!
	@IBOutlet weak var separateItemsSwitch: NSButton!
	@IBOutlet weak var autoLabelSwitch: NSButton!
	@IBOutlet weak var launchAtLoginSwitch: NSButton!
	@IBOutlet weak var hideMainWindowSwitch: NSButton!

	@IBOutlet weak var hotkeyCmd: NSButton!
	@IBOutlet weak var hotkeyOption: NSButton!
	@IBOutlet weak var hotkeyShift: NSButton!
	@IBOutlet weak var hotkeyChar: NSPopUpButton!
	@IBOutlet weak var hotkeyCtrl: NSButton!
	private let keyMap = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6]

	@IBAction func doneSelected(_ sender: NSButton) {
		dismiss(nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		displayNotesSwitch.integerValue = PersistedOptions.displayNotesInMainView ? 1 : 0
		displayLabelsSwitch.integerValue = PersistedOptions.displayLabelsInMainView ? 1 : 0
		separateItemsSwitch.integerValue = PersistedOptions.separateItemPreference ? 1 : 0
		autoLabelSwitch.integerValue = PersistedOptions.dontAutoLabelNewItems ? 1 : 0
		launchAtLoginSwitch.integerValue = PersistedOptions.launchAtLogin ? 1 : 0
		hideMainWindowSwitch.integerValue = PersistedOptions.hideMainWindowAtStartup ? 1 : 0

		NotificationCenter.default.addObserver(self, selector: #selector(updateSyncSwitches), name: .CloudManagerStatusChanged, object: nil)
		updateSyncSwitches()
		setupHotkeySection()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	private func setupHotkeySection() {
		if let m = hotkeyChar.menu {
			m.removeAllItems()
			m.addItem(withTitle: "None", action: #selector(hotkeyCharChanged), keyEquivalent: "")
			for char in "abcdefghijklmnopqrstuvwxyz".uppercased() {
				m.addItem(withTitle: "\(char)", action: #selector(hotkeyCharChanged), keyEquivalent: "")
			}
		}
		hotkeyCmd.integerValue = PersistedOptions.hotkeyCmd ? 1 : 0
		hotkeyOption.integerValue = PersistedOptions.hotkeyOption ? 1 : 0
		hotkeyShift.integerValue = PersistedOptions.hotkeyShift ? 1 : 0
		hotkeyCtrl.integerValue = PersistedOptions.hotkeyCtrl ? 1 : 0
		if PersistedOptions.hotkeyChar >= 0, let index = keyMap.index(of: PersistedOptions.hotkeyChar), let item = hotkeyChar.item(at: index + 1) {
			hotkeyChar.select(item)
		} else {
			hotkeyChar.select(hotkeyChar.menu?.items.first)
		}
		updateHotkeyState()
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		view.window!.initialFirstResponder = doneButton
	}

	@IBAction func launchAtLoginSwitchChanged(_ sender: NSButton) {
		PersistedOptions.launchAtLogin = sender.integerValue == 1
	}

	@IBAction func hideMainWindowAtLaunchSwitchChanged(_ sender: NSButton) {
		PersistedOptions.hideMainWindowAtStartup = sender.integerValue == 1
	}

	@objc private func hotkeyCharChanged() {
		if hotkeyChar.indexOfSelectedItem == 0 {
			PersistedOptions.hotkeyChar = -1
		} else {
			PersistedOptions.hotkeyChar = keyMap[hotkeyChar.indexOfSelectedItem - 1]
		}
		updateHotkeyState()
	}

	@IBAction func hotkeyCmdChanged(_ sender: NSButton) {
		PersistedOptions.hotkeyCmd = sender.integerValue == 1
		updateHotkeyState()
	}

	@IBAction func hotkeyOptionChanged(_ sender: NSButton) {
		PersistedOptions.hotkeyOption = sender.integerValue == 1
		updateHotkeyState()
	}

	@IBAction func hotkeyShiftChanged(_ sender: NSButton) {
		PersistedOptions.hotkeyShift = sender.integerValue == 1
		updateHotkeyState()
	}

	@IBAction func hotkeyCtrlChaned(_ sender: NSButton) {
		PersistedOptions.hotkeyCtrl = sender.integerValue == 1
		updateHotkeyState()
	}

	private func updateHotkeyState() {
		let enable = hotkeyCmd.integerValue == 1 || hotkeyOption.integerValue == 1 || hotkeyCtrl.integerValue == 1
		hotkeyShift.isEnabled = enable
		hotkeyChar.isEnabled = enable
		if !enable {
			hotkeyChar.select(hotkeyChar.menu?.item(at: 0))
			hotkeyShift.integerValue = 0
			PersistedOptions.hotkeyChar = 0
			PersistedOptions.hotkeyShift = false
		}
		AppDelegate.updateHotkey()
	}

	@objc private func updateSyncSwitches() {
		assert(Thread.isMainThread)
		if CloudManager.syncTransitioning || CloudManager.syncing {
			syncSwitch.isEnabled = false
			syncNowButton.isEnabled = false
			deleteAllButton.isEnabled = false
			eraseAlliCloudDataButton.isEnabled = false
			syncSwitch.title = CloudManager.syncString
			syncSpinner.startAnimation(nil)
		} else {
			syncSwitch.isEnabled = true
			syncNowButton.isEnabled = CloudManager.syncSwitchedOn
			deleteAllButton.isEnabled = true
			eraseAlliCloudDataButton.isEnabled = true
			syncSwitch.title = "iCloud Sync"
			syncSpinner.stopAnimation(nil)
			syncSwitch.integerValue = CloudManager.syncSwitchedOn ? 1 : 0
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

	@IBAction func syncNowSelected(_ sender: NSButton) {
		CloudManager.sync { [weak self] error in
			if let error = error, let s = self {
				let a = NSAlert(error: error)
				a.beginSheetModal(for: s.view.window!) { response in }
			}
		}
	}

	@IBAction func displayNotesSwitchSelected(_ sender: NSButton) {
		PersistedOptions.displayNotesInMainView = sender.integerValue == 1
		ViewController.shared.reloadData()
	}

	@IBAction func displayLabelsSwitchSelected(_ sender: NSButton) {
		PersistedOptions.displayLabelsInMainView = sender.integerValue == 1
		ViewController.shared.reloadData()
	}

	@IBAction func multipleSwitchChanged(_ sender: NSButton) {
		PersistedOptions.separateItemPreference = sender.integerValue == 1
	}

	@IBAction func autoLabelSwitchChanged(_ sender: NSButton) {
		PersistedOptions.dontAutoLabelNewItems = sender.integerValue == 1
	}

	@IBAction func resetWarningsSelected(_ sender: NSButton) {
		PersistedOptions.unconfirmedDeletes = false
		sender.isEnabled = false
	}

	@IBAction func syncSwitchChanged(_ sender: NSButton) {
		syncSwitch.isEnabled = false

		if CloudManager.syncSwitchedOn {
			CloudManager.deactivate(force: false) { error in
				DispatchQueue.main.async {
					if let error = error {
						genericAlert(title: "Could not change state", message: error.finalDescription, on: self)
					}
				}
			}
		} else {
			CloudManager.activate { error in
				DispatchQueue.main.async {
					if let error = error {
						genericAlert(title: "Could not change state", message: error.finalDescription, on: self)
					}
				}
			}
		}
	}

	@IBAction func eraseiCloudDataSelected(_ sender: NSButton) {
		if CloudManager.syncSwitchedOn || CloudManager.syncTransitioning || CloudManager.syncing {
			genericAlert(title: "Sync is on", message: "This operation cannot be performed while sync is switched on. Please switch it off first.", on: self)
		} else {
			let a = NSAlert()
			a.messageText = "Are you sure?"
			a.informativeText = "This will remove any data that Gladys has stored in iCloud from any device. If you have other devices with sync switched on, it will stop working there until it is re-enabled."
			a.addButton(withTitle: "Delete iCloud Data")
			a.addButton(withTitle: "Cancel")

			a.beginSheetModal(for: view.window!) { [weak self] response in
				if response == .alertFirstButtonReturn {
					self?.eraseiCloudData()
				}
			}
		}
	}

	private func eraseiCloudData() {
		syncNowButton.isEnabled = false
		syncSwitch.isEnabled = false
		syncNowButton.isEnabled = false
		eraseAlliCloudDataButton.isEnabled = false
		CloudManager.eraseZoneIfNeeded { [weak self] error in
			guard let s = self else { return }
			s.eraseAlliCloudDataButton.isEnabled = true
			s.syncSwitch.isEnabled = true
			s.syncSwitch.isEnabled = true
			if let error = error {
				genericAlert(title: "Error", message: error.finalDescription, on: s)
			} else {
				genericAlert(title: "Done", message: "All Gladys data has been removed from iCloud", on: s)
			}
		}
	}


}
