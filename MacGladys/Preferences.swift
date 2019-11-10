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
	@IBOutlet private weak var syncSwitch: NSButton!
	@IBOutlet private weak var syncSpinner: NSProgressIndicator!
	@IBOutlet private weak var syncNowButton: NSButton!

	@IBOutlet private weak var deleteAllButton: NSButton!
	@IBOutlet private weak var doneButton: NSButton!
	@IBOutlet private weak var eraseAlliCloudDataButton: NSButton!

	@IBOutlet private weak var displayNotesSwitch: NSButton!
	@IBOutlet private weak var displayLabelsSwitch: NSButton!
	@IBOutlet private weak var separateItemsSwitch: NSButton!
	@IBOutlet private weak var autoLabelSwitch: NSButton!
	@IBOutlet private weak var inclusiveSearchTermsSwitch: NSButton!
    @IBOutlet private weak var autoConvertUrlsSwitch: NSButton!
    @IBOutlet private weak var convertLabelsToTagsSwitch: NSButton!

	@IBOutlet private weak var launchAtLoginSwitch: NSButton!
	@IBOutlet private weak var hideMainWindowSwitch: NSButton!

	@IBOutlet private weak var menuBarModeSwitch: NSButton!
	@IBOutlet private weak var alwaysOnTopSwitch: NSButton!
    @IBOutlet private weak var disableUrlSupportSwitch: NSButton!
    
	@IBOutlet private weak var autoDownloadSwitch: NSButton!
	@IBOutlet private weak var exclusiveMultipleLabelsSwitch: NSButton!
	@IBOutlet private weak var selectionActionPicker: NSPopUpButton!
    @IBOutlet private weak var touchbarActionPicker: NSPopUpButton!

	@IBOutlet private weak var hotkeyCmd: NSButton!
	@IBOutlet private weak var hotkeyOption: NSButton!
	@IBOutlet private weak var hotkeyShift: NSButton!
	@IBOutlet private weak var hotkeyChar: NSPopUpButton!
	@IBOutlet private weak var hotkeyCtrl: NSButton!
	private let keyMap = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6]

	@IBAction private func doneSelected(_ sender: NSButton) {
		dismiss(nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		displayNotesSwitch.integerValue = PersistedOptions.displayNotesInMainView ? 1 : 0
		displayLabelsSwitch.integerValue = PersistedOptions.displayLabelsInMainView ? 1 : 0
		separateItemsSwitch.integerValue = PersistedOptions.separateItemPreference ? 1 : 0
		autoLabelSwitch.integerValue = PersistedOptions.dontAutoLabelNewItems ? 1 : 0
		inclusiveSearchTermsSwitch.integerValue = PersistedOptions.inclusiveSearchTerms ? 1 : 0
        autoConvertUrlsSwitch.integerValue = PersistedOptions.automaticallyDetectAndConvertWebLinks ? 1 : 0
        convertLabelsToTagsSwitch.integerValue = PersistedOptions.readAndStoreFinderTagsAsLabels ? 1 : 0
        launchAtLoginSwitch.integerValue = PersistedOptions.launchAtLogin ? 1 : 0
		hideMainWindowSwitch.integerValue = PersistedOptions.hideMainWindowAtStartup ? 1 : 0
		menuBarModeSwitch.integerValue = PersistedOptions.menubarIconMode ? 1 : 0
		alwaysOnTopSwitch.integerValue = PersistedOptions.alwaysOnTop ? 1 : 0
        disableUrlSupportSwitch.integerValue = PersistedOptions.blockGladysUrlRequests ? 1 : 0
        exclusiveMultipleLabelsSwitch.integerValue = PersistedOptions.exclusiveMultipleLabels ? 1 : 0
		autoDownloadSwitch.integerValue = PersistedOptions.autoArchiveUrlComponents ? 1 : 0
		selectionActionPicker.selectItem(at: PersistedOptions.actionOnTap.rawValue)
        touchbarActionPicker.selectItem(at: PersistedOptions.actionOnTouchbar.rawValue)

		NotificationCenter.default.addObserver(self, selector: #selector(updateSyncSwitches), name: .CloudManagerStatusChanged, object: nil)
		updateSyncSwitches()
		setupHotkeySection()
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
		if PersistedOptions.hotkeyChar >= 0, let index = keyMap.firstIndex(of: PersistedOptions.hotkeyChar), let item = hotkeyChar.item(at: index + 1) {
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

    @IBAction private func convertLabelsToTagsSwitchSelected(_ sender: NSButton) {
        PersistedOptions.readAndStoreFinderTagsAsLabels = sender.integerValue == 1
    }
    
	@IBAction private func menuBarModeSwitchChanged(_ sender: NSButton) {
		PersistedOptions.menubarIconMode = sender.integerValue == 1
		AppDelegate.shared?.updateMenubarIconMode(showing: true, forceUpdateMenu: true)
	}

	@IBAction private func exclusiveMultipleLabelsSwitchChanged(_ sender: NSButton) {
		PersistedOptions.exclusiveMultipleLabels = sender.integerValue == 1
		NotificationCenter.default.post(name: .LabelSelectionChanged, object: nil)
	}

	@IBAction private func autoDownloadSwitchChanged(_ sender: NSButton) {
		PersistedOptions.autoArchiveUrlComponents = sender.integerValue == 1
	}
    
    @IBAction private func blockUrlSwitchChanged(_ sender: NSButton) {
        PersistedOptions.blockGladysUrlRequests = sender.integerValue == 1
    }

	@IBAction private func selectionActionPickerChanged(_ sender: NSPopUpButton) {
		if let action = DefaultTapAction(rawValue: sender.indexOfSelectedItem) {
			PersistedOptions.actionOnTap = action
		}
	}

    @IBAction private func touchbarActionPickerChanged(_ sender: NSPopUpButton) {
        if let action = DefaultTapAction(rawValue: sender.indexOfSelectedItem) {
            PersistedOptions.actionOnTouchbar = action
        }
    }

	@IBAction private func launchAtLoginSwitchChanged(_ sender: NSButton) {
		PersistedOptions.launchAtLogin = sender.integerValue == 1
	}

	@IBAction private func hideMainWindowAtLaunchSwitchChanged(_ sender: NSButton) {
		PersistedOptions.hideMainWindowAtStartup = sender.integerValue == 1
	}

	@IBAction private func alawysOnTopSwitchChanged(_ sender: NSButton) {
		PersistedOptions.alwaysOnTop = sender.integerValue == 1
		NotificationCenter.default.post(name: .AlwaysOnTopChanged, object: nil)
	}

	@objc private func hotkeyCharChanged() {
		if hotkeyChar.indexOfSelectedItem == 0 {
			PersistedOptions.hotkeyChar = -1
		} else {
			PersistedOptions.hotkeyChar = keyMap[hotkeyChar.indexOfSelectedItem - 1]
		}
		updateHotkeyState()
	}

	@IBAction private func hotkeyCmdChanged(_ sender: NSButton) {
		PersistedOptions.hotkeyCmd = sender.integerValue == 1
		updateHotkeyState()
	}

	@IBAction private func hotkeyOptionChanged(_ sender: NSButton) {
		PersistedOptions.hotkeyOption = sender.integerValue == 1
		updateHotkeyState()
	}

	@IBAction private func hotkeyShiftChanged(_ sender: NSButton) {
		PersistedOptions.hotkeyShift = sender.integerValue == 1
		updateHotkeyState()
	}

	@IBAction private func hotkeyCtrlChaned(_ sender: NSButton) {
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

	@IBAction private func deleteLocalItemsSelected(_ sender: NSButton) {

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

		confirm(title: title, message: subtitle, action: actionName, cancel: "Cancel") { confirmed in
			if confirmed {
                Model.sharedFilter.resetEverything()
			}
		}
	}

	@IBAction private func syncNowSelected(_ sender: NSButton) {
		CloudManager.sync { [weak self] error in
			if let error = error, let s = self {
				let a = NSAlert()
				a.alertStyle = .warning
				a.messageText = "Sync Failed"
				a.informativeText = error.finalDescription
				a.beginSheetModal(for: s.view.window!) { response in }
			}
		}
	}

	@IBAction private func displayNotesSwitchSelected(_ sender: NSButton) {
		PersistedOptions.displayNotesInMainView = sender.integerValue == 1
		ViewController.shared.itemView.reloadData()
	}

	@IBAction private func displayLabelsSwitchSelected(_ sender: NSButton) {
		PersistedOptions.displayLabelsInMainView = sender.integerValue == 1
		ViewController.shared.itemView.reloadData()
	}

	@IBAction private func multipleSwitchChanged(_ sender: NSButton) {
		PersistedOptions.separateItemPreference = sender.integerValue == 1
	}

	@IBAction private func autoLabelSwitchChanged(_ sender: NSButton) {
		PersistedOptions.dontAutoLabelNewItems = sender.integerValue == 1
	}

	@IBAction private func inclusiveSearchTermsSwitchChanged(_ sender: NSButton) {
		PersistedOptions.inclusiveSearchTerms = sender.integerValue == 1
		Model.sharedFilter.forceUpdateFilter(signalUpdate: true)
	}
    
    @IBAction private func automaticallyConvertUrlsSwitchChanged(_ sender: NSButton) {
        PersistedOptions.automaticallyDetectAndConvertWebLinks = sender.integerValue == 1
    }

	@IBAction private func resetWarningsSelected(_ sender: NSButton) {
		PersistedOptions.unconfirmedDeletes = false
		sender.isEnabled = false
	}

	@IBAction private func syncSwitchChanged(_ sender: NSButton) {
		syncSwitch.isEnabled = false

		if CloudManager.syncSwitchedOn {
			let sharingOwn = Model.sharingMyItems
			let importing = Model.containsImportedShares
			if sharingOwn && importing {
				confirm(title: "You have shared items",
						message: "Turning sync off means that your currently shared items will be removed from others' collections, and their shared items will not be visible in your own collection. Is that OK?",
						action: "Turn Off Sync",
						cancel: "Cancel") { confirmed in if confirmed { CloudManager.proceedWithDeactivation() } else { self.abortDeactivate() } }
			} else if sharingOwn {
				confirm(title: "You are sharing items",
						message: "Turning sync off means that your currently shared items will be removed from others' collections. Is that OK?",
						action: "Turn Off Sync",
						cancel: "Cancel") { confirmed in if confirmed { CloudManager.proceedWithDeactivation() } else { self.abortDeactivate() } }
			} else if importing {
				confirm(title: "You have items that are shared from others",
						message: "Turning sync off means that those items will no longer be accessible. Re-activating sync will restore them later though. Is that OK?",
						action: "Turn Off Sync",
						cancel: "Cancel") { confirmed in if confirmed { CloudManager.proceedWithDeactivation() } else { self.abortDeactivate() } }
			} else {
				CloudManager.proceedWithDeactivation()
			}
		} else {
			if Model.drops.count > 0 {
				let contentSize = diskSizeFormatter.string(fromByteCount: Model.sizeInBytes)
				confirm(title: "Upload Existing Items?",
						message: "If you have previously synced Gladys items they will merge with existing items.\n\nThis may upload up to \(contentSize) of data.\n\nIs it OK to proceed?",
				action: "Proceed", cancel: "Cancel") { confirmed in
					if confirmed {
						CloudManager.proceedWithActivation()
					} else {
						self.abortActivate()
					}
				}
			} else {
				CloudManager.proceedWithActivation()
			}
		}
	}

	private func abortDeactivate() {
		syncSwitch.integerValue = 1
		syncSwitch.isEnabled = true
	}

	private func abortActivate() {
		syncSwitch.integerValue = 0
		syncSwitch.isEnabled = true
	}

	@IBAction private func eraseiCloudDataSelected(_ sender: NSButton) {
		if CloudManager.syncSwitchedOn || CloudManager.syncTransitioning || CloudManager.syncing {
			genericAlert(title: "Sync is on", message: "This operation cannot be performed while sync is switched on. Please switch it off first.")
		} else {
			confirm(title: "Are you sure?",
					message: "This will remove any data that Gladys has stored in iCloud from any device. If you have other devices with sync switched on, it will stop working there until it is re-enabled.",
					action: "Delete iCloud Data",
					cancel: "Cancel") { [weak self] confirmed in
						if confirmed {
							self?.eraseiCloudData()
						}
			}
		}
	}

	private func confirm(title: String, message: String, action: String, cancel: String, completion: @escaping (Bool)->Void) {
		let a = NSAlert()
		a.messageText = title
		a.informativeText = message
		a.addButton(withTitle: action)
		a.addButton(withTitle: cancel)
		a.beginSheetModal(for: view.window!) { response in
			completion(response == .alertFirstButtonReturn)
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
				genericAlert(title: "Error", message: error.finalDescription)
			} else {
				genericAlert(title: "Done", message: "All Gladys data has been removed from iCloud")
			}
		}
	}


}
