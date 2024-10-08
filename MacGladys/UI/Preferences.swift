import AppKit
import Carbon.HIToolbox
import GladysAppKit
import GladysCommon
import GladysUI
import Speech

final class Preferences: NSViewController, NSTextFieldDelegate {
    @IBOutlet private var syncSwitch: NSButton!
    @IBOutlet private var syncSpinner: NSProgressIndicator!
    @IBOutlet private var syncNowButton: NSButton!
    @IBOutlet private var syncStatus: NSTextField!
    @IBOutlet private var syncStatusHolder: NSStackView!

    @IBOutlet private var deleteAllButton: NSButton!
    @IBOutlet private var eraseAlliCloudDataButton: NSButton!

    @IBOutlet private var displayNotesSwitch: NSButton!
    @IBOutlet private var displayLabelsSwitch: NSButton!
    @IBOutlet private var separateItemsSwitch: NSButton!
    @IBOutlet private var autoLabelSwitch: NSButton!

    @IBOutlet private var searchLogicSelector: NSPopUpButton!
    @IBOutlet private var autoConvertUrlsSwitch: NSButton!
    @IBOutlet private var convertLabelsToTagsSwitch: NSButton!
    @IBOutlet private var autoShowWhenDraggingSwitch: NSButton!
    @IBOutlet private var autoShowOnEdgePicker: NSPopUpButton!
    @IBOutlet private var autoDetectLabelsFromTitles: NSButton!
    @IBOutlet private var autoDetectLabelsFromThumbnails: NSButton!
    @IBOutlet private var autoDetectTextFromThumbnails: NSButton!
    @IBOutlet private var transcribeSpeechFromMedia: NSButton!
    @IBOutlet private var applyMlSettingsToLinks: NSButton!

    @IBOutlet private var clipboardSnooping: NSButton!
    @IBOutlet private var clipboardSnoopingAll: NSButton!
    @IBOutlet private var clipboardLabelling: NSTextField!

    @IBOutlet private var badgeItemWithVisibleItemCount: NSButton!

    @IBOutlet private var fadeAfterLabel: NSTextField!
    @IBOutlet private var fadeAfterCounter: NSStepper!

    @IBOutlet private var launchAtLoginSwitch: NSButton!
    @IBOutlet private var hideMainWindowSwitch: NSButton!

    @IBOutlet private var menuBarModeSwitch: NSButton!
    @IBOutlet private var alwaysOnTopSwitch: NSButton!
    @IBOutlet private var disableUrlSupportSwitch: NSButton!

    @IBOutlet private var autoDownloadSwitch: NSButton!
    @IBOutlet private var exclusiveMultipleLabelsSwitch: NSButton!
    @IBOutlet private var selectionActionPicker: NSPopUpButton!
    @IBOutlet private var touchbarActionPicker: NSPopUpButton!

    @IBOutlet private var hotkeyCmd: NSButton!
    @IBOutlet private var hotkeyOption: NSButton!
    @IBOutlet private var hotkeyShift: NSButton!
    @IBOutlet private var hotkeyChar: NSPopUpButton!
    @IBOutlet private var hotkeyCtrl: NSButton!

    private let keyMap = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
        kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
        kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
        kVK_ANSI_Y, kVK_ANSI_Z, kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ]

    private func createStringForKey(keyCode: CGKeyCode) -> String? {
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

        var realLength = 0
        var keysDown: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)

        UCKeyTranslate(keyboardLayout,
                       keyCode,
                       UInt16(kUCKeyActionDisplay),
                       0,
                       UInt32(LMGetKbdType()),
                       UInt32(kUCKeyTranslateNoDeadKeysBit),
                       &keysDown,
                       chars.count,
                       &realLength,
                       &chars)

        if realLength == 0 {
            return nil
        }
        return (CFStringCreateWithCharacters(nil, chars, realLength) as String).uppercased()
    }

    @IBAction private func doneSelected(_: NSButton) {
        dismiss(nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        autoDetectLabelsFromTitles.integerValue = PersistedOptions.autoGenerateLabelsFromText ? 1 : 0
        autoDetectLabelsFromThumbnails.integerValue = PersistedOptions.autoGenerateLabelsFromImage ? 1 : 0
        autoDetectTextFromThumbnails.integerValue = PersistedOptions.autoGenerateTextFromImage ? 1 : 0
        displayNotesSwitch.integerValue = PersistedOptions.displayNotesInMainView ? 1 : 0
        displayLabelsSwitch.integerValue = PersistedOptions.displayLabelsInMainView ? 1 : 0
        separateItemsSwitch.integerValue = PersistedOptions.separateItemPreference ? 1 : 0
        autoLabelSwitch.integerValue = PersistedOptions.dontAutoLabelNewItems ? 1 : 0
        autoConvertUrlsSwitch.integerValue = PersistedOptions.automaticallyDetectAndConvertWebLinks ? 1 : 0
        convertLabelsToTagsSwitch.integerValue = PersistedOptions.readAndStoreFinderTagsAsLabels ? 1 : 0
        launchAtLoginSwitch.integerValue = PersistedOptions.launchAtLogin ? 1 : 0
        hideMainWindowSwitch.integerValue = PersistedOptions.hideMainWindowAtStartup ? 1 : 0
        menuBarModeSwitch.integerValue = PersistedOptions.menubarIconMode ? 1 : 0
        alwaysOnTopSwitch.integerValue = PersistedOptions.alwaysOnTop ? 1 : 0
        disableUrlSupportSwitch.integerValue = PersistedOptions.blockGladysUrlRequests ? 1 : 0
        exclusiveMultipleLabelsSwitch.integerValue = PersistedOptions.exclusiveMultipleLabels ? 1 : 0
        autoDownloadSwitch.integerValue = PersistedOptions.autoArchiveUrlComponents ? 1 : 0
        autoShowWhenDraggingSwitch.integerValue = PersistedOptions.autoShowWhenDragging ? 1 : 0
        selectionActionPicker.selectItem(at: PersistedOptions.actionOnTap.rawValue)
        touchbarActionPicker.selectItem(at: PersistedOptions.actionOnTouchbar.rawValue)
        autoShowOnEdgePicker.selectItem(at: PersistedOptions.autoShowFromEdge)
        applyMlSettingsToLinks.integerValue = PersistedOptions.includeUrlImagesInMlLogic ? 1 : 0
        transcribeSpeechFromMedia.integerValue = PersistedOptions.transcribeSpeechFromMedia ? 1 : 0
        clipboardSnooping.integerValue = PersistedOptions.clipboardSnooping ? 1 : 0
        clipboardSnoopingAll.integerValue = PersistedOptions.clipboardSnoopingAll ? 1 : 0
        clipboardLabelling.stringValue = PersistedOptions.clipboardSnoopingLabel
        badgeItemWithVisibleItemCount.integerValue = PersistedOptions.badgeIconWithItemCount ? 1 : 0
        updateFadeLabel()

        if PersistedOptions.useExplicitSearch {
            if PersistedOptions.inclusiveSearchTerms {
                searchLogicSelector.selectItem(at: 1)
            } else {
                searchLogicSelector.selectItem(at: 2)
            }
        } else {
            searchLogicSelector.selectItem(at: 0)
        }

        notifications(for: .CloudManagerStatusChanged) { [weak self] _ in
            await self?.updateSyncSwitches()
        }

        Task {
            await updateSyncSwitches()
        }
        setupHotkeySection()
    }

    private func updateFadeLabel() {
        let value = PersistedOptions.autoHideAfter
        fadeAfterCounter.integerValue = value
        if value == 0 {
            fadeAfterLabel.stringValue = "Stay visible and wait for mouse to enter"
        } else if value == 1 {
            fadeAfterLabel.stringValue = "Hide again after 1 second if mouse doesn't enter"
        } else {
            fadeAfterLabel.stringValue = "Hide again after \(value) seconds if mouse doesn't enter"
        }
    }

    @IBAction private func autoFadeChanged(_ sender: NSStepperCell) {
        PersistedOptions.autoHideAfter = sender.integerValue
        updateFadeLabel()
    }

    private func setupHotkeySection() {
        if let m = hotkeyChar.menu {
            m.removeAllItems()
            m.addItem(withTitle: "None", action: #selector(hotkeyCharChanged), keyEquivalent: "")
            var count = 0
            for char in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
                let code = keyMap[count]
                if let char = createStringForKey(keyCode: CGKeyCode(code)) {
                    m.addItem(withTitle: char, action: #selector(hotkeyCharChanged), keyEquivalent: "")
                } else {
                    m.addItem(withTitle: String(char), action: #selector(hotkeyCharChanged), keyEquivalent: "")
                }
                count += 1
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
        view.window?.styleMask.remove(.resizable)
    }

    func controlTextDidChange(_: Notification) {
        PersistedOptions.clipboardSnoopingLabel = clipboardLabelling.stringValue
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
        sendNotification(name: .LabelSelectionChanged, object: nil)
    }

    @IBAction func clipboardSnoopingSelected(_ sender: NSButton) {
        PersistedOptions.clipboardSnooping = sender.integerValue == 1
        sendNotification(name: .ClipboardSnoopingChanged, object: nil)
    }

    @IBAction func clipboardSnoopingAllSelected(_ sender: NSButton) {
        PersistedOptions.clipboardSnoopingAll = sender.integerValue == 1
    }

    @IBAction private func autoDownloadSwitchChanged(_ sender: NSButton) {
        PersistedOptions.autoArchiveUrlComponents = sender.integerValue == 1
    }

    @IBAction private func autoDetectLabelsFromTitlesChanged(_ sender: NSButton) {
        PersistedOptions.autoGenerateLabelsFromText = sender.integerValue == 1
    }

    @IBAction private func autoDetectLabelsFromThumbnailsChanged(_ sender: NSButton) {
        PersistedOptions.autoGenerateLabelsFromImage = sender.integerValue == 1
    }

    @IBAction private func autoDetectTextFromThumbnailsChanged(_ sender: NSButton) {
        PersistedOptions.autoGenerateTextFromImage = sender.integerValue == 1
    }

    @IBAction private func applyMlSettingsToLinksChanged(_ sender: NSButton) {
        PersistedOptions.includeUrlImagesInMlLogic = sender.integerValue == 1
    }

    @IBAction private func badgeIconWithItemCountSelected(_ sender: NSButton) {
        PersistedOptions.badgeIconWithItemCount = sender.integerValue == 1
        Model.updateBadge()
    }

    @IBAction private func transcribeSpeechFromMediaChanged(_ sender: NSButton) {
        if sender.integerValue == 1 {
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:
                    Task { @MainActor in
                        if let testRecognizer = SFSpeechRecognizer(), testRecognizer.isAvailable, testRecognizer.supportsOnDeviceRecognition {
                            PersistedOptions.transcribeSpeechFromMedia = sender.integerValue == 1
                            await genericAlert(title: "Activated", message: "Please note that this feature can significantly increase the processing time of media with long durations.")
                        } else {
                            sender.integerValue = 0
                            PersistedOptions.transcribeSpeechFromMedia = false
                            await genericAlert(title: "Could not activate", message: "This device does not support on-device speech recognition.")
                        }
                    }
                case .denied, .notDetermined, .restricted:
                    Task { @MainActor in
                        sender.integerValue = 0
                        PersistedOptions.transcribeSpeechFromMedia = false
                    }
                @unknown default:
                    Task { @MainActor in
                        sender.integerValue = 0
                        PersistedOptions.transcribeSpeechFromMedia = false
                    }
                }
            }
        } else {
            PersistedOptions.transcribeSpeechFromMedia = false
        }
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
        sendNotification(name: .AlwaysOnTopChanged, object: nil)
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

    @IBAction private func autoShowWhenDraggingChanged(_ sender: NSButton) {
        PersistedOptions.autoShowWhenDragging = sender.integerValue == 1
    }

    @IBAction private func autoShowFromEdgeChanged(_ sender: NSPopUpButton) {
        PersistedOptions.autoShowFromEdge = sender.indexOfSelectedItem
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

    private func updateSyncSwitches() async {
        let transitioning = await CloudManager.syncTransitioning
        let syncing = await CloudManager.syncing
        if transitioning || syncing {
            syncSwitch.isEnabled = false
            syncNowButton.isEnabled = false
            deleteAllButton.isEnabled = false
            eraseAlliCloudDataButton.isHidden = true
            syncStatus.stringValue = await CloudManager.makeSyncString()
            syncStatusHolder.isHidden = false
            syncSpinner.startAnimation(nil)
        } else {
            let switchOn = await CloudManager.syncSwitchedOn
            syncSwitch.isEnabled = true
            syncNowButton.isEnabled = switchOn
            deleteAllButton.isEnabled = true
            eraseAlliCloudDataButton.isHidden = false
            syncStatus.stringValue = ""
            syncStatusHolder.isHidden = true
            syncSpinner.stopAnimation(nil)
            syncSwitch.integerValue = switchOn ? 1 : 0
        }
    }

    @IBAction private func deleteLocalItemsSelected(_: NSButton) {
        Task {
            let title: String
            let subtitle: String
            let actionName: String

            if await CloudManager.syncSwitchedOn {
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
                    Model.resetEverything()
                }
            }
        }
    }

    @IBAction private func syncNowSelected(_: NSButton) {
        Task {
            do {
                try await CloudManager.sync()
            } catch {
                let a = NSAlert()
                a.alertStyle = .warning
                a.messageText = "Sync Failed"
                a.informativeText = error.localizedDescription
                a.beginSheetModal(for: view.window!) { _ in }
            }
        }
    }

    @IBAction private func displayNotesSwitchSelected(_ sender: NSButton) {
        PersistedOptions.displayNotesInMainView = sender.integerValue == 1
        sendNotification(name: .ItemCollectionNeedsDisplay, object: nil)
    }

    @IBAction private func displayLabelsSwitchSelected(_ sender: NSButton) {
        PersistedOptions.displayLabelsInMainView = sender.integerValue == 1
        sendNotification(name: .ItemCollectionNeedsDisplay, object: nil)
    }

    @IBAction private func multipleSwitchChanged(_ sender: NSButton) {
        PersistedOptions.separateItemPreference = sender.integerValue == 1
    }

    @IBAction private func autoLabelSwitchChanged(_ sender: NSButton) {
        PersistedOptions.dontAutoLabelNewItems = sender.integerValue == 1
    }

    @IBAction private func inclusiveSearchTermsSwitchChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 0:
            PersistedOptions.useExplicitSearch = false
            PersistedOptions.inclusiveSearchTerms = false
        case 1:
            PersistedOptions.useExplicitSearch = true
            PersistedOptions.inclusiveSearchTerms = true
        case 2:
            PersistedOptions.useExplicitSearch = true
            PersistedOptions.inclusiveSearchTerms = false
        default:
            break
        }
        sendNotification(name: .FiltersShouldUpdate)
    }

    @IBAction private func automaticallyConvertUrlsSwitchChanged(_ sender: NSButton) {
        PersistedOptions.automaticallyDetectAndConvertWebLinks = sender.integerValue == 1
    }

    @IBAction private func resetWarningsSelected(_ sender: NSButton) {
        PersistedOptions.unconfirmedDeletes = false
        sender.isEnabled = false
    }

    @IBAction private func syncSwitchChanged(_: NSButton) {
        syncSwitch.isEnabled = false

        Task {
            if await CloudManager.syncSwitchedOn {
                let sharingOwn = DropStore.sharingMyItems
                let importing = DropStore.containsImportedShares
                if sharingOwn, importing {
                    confirm(title: "You have shared items",
                            message: "Turning sync off means that your currently shared items will be removed from others' collections, and their shared items will not be visible in your own collection. Is that OK?",
                            action: "Turn Off Sync",
                            cancel: "Cancel") { confirmed in if confirmed { self.deactivationConfirmed() } else { self.abortDeactivate() } }
                } else if sharingOwn {
                    confirm(title: "You are sharing items",
                            message: "Turning sync off means that your currently shared items will be removed from others' collections. Is that OK?",
                            action: "Turn Off Sync",
                            cancel: "Cancel") { confirmed in if confirmed { self.deactivationConfirmed() } else { self.abortDeactivate() } }
                } else if importing {
                    confirm(title: "You have items that are shared from others",
                            message: "Turning sync off means that those items will no longer be accessible. Re-activating sync will restore them later though. Is that OK?",
                            action: "Turn Off Sync",
                            cancel: "Cancel") { confirmed in if confirmed { self.deactivationConfirmed() } else { self.abortDeactivate() } }
                } else {
                    self.deactivationConfirmed()
                }
            } else {
                if DropStore.allDrops.isEmpty {
                    activationConfirmed()
                } else {
                    let contentSize = await DropStore.sizeInBytes()
                    let contentSizeString = diskSizeFormatter.string(fromByteCount: contentSize)
                    self.confirm(title: "Upload Existing Items?",
                                 message: "If you have previously synced Gladys items they will merge with existing items.\n\nThis may upload up to \(contentSizeString) of data.\n\nIs it OK to proceed?",
                                 action: "Proceed", cancel: "Cancel") { confirmed in
                        if confirmed {
                            self.activationConfirmed()
                        } else {
                            self.abortActivate()
                        }
                    }
                }
            }
        }
    }

    private func activationConfirmed() {
        Task {
            do {
                try await CloudManager.startActivation()
            } catch {
                let offerSettings = (error as? GladysError)?.suggestSettings ?? false
                await genericAlert(title: "Could not activate", message: error.localizedDescription, offerSettingsShortcut: offerSettings)
            }
        }
    }

    private func deactivationConfirmed() {
        Task {
            do {
                try await CloudManager.proceedWithDeactivation()
            } catch {
                await genericAlert(title: "Could not deactivate", message: error.localizedDescription)
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

    @IBAction private func eraseiCloudDataSelected(_: NSButton) {
        Task {
            let syncOn = await CloudManager.syncSwitchedOn
            let transitioning = await CloudManager.syncTransitioning
            let syncing = await CloudManager.syncing
            if syncOn || transitioning || syncing {
                await genericAlert(title: "Sync is on", message: "This operation cannot be performed while sync is switched on. Please switch it off first.")
            } else {
                confirm(title: "Are you sure?",
                        message: "This will remove any data that Gladys has stored in iCloud from any device. If you have other devices with sync switched on, it will stop working there until it is re-enabled.",
                        action: "Delete iCloud Data",
                        cancel: "Cancel") { [weak self] confirmed in
                    if let self, confirmed {
                        eraseiCloudData()
                    }
                }
            }
        }
    }

    private func confirm(title: String, message: String, action: String, cancel: String, completion: @escaping (Bool) -> Void) {
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
        Task {
            do {
                try await CloudManager.eraseZoneIfNeeded()
                await genericAlert(title: "Done", message: "All Gladys data has been removed from iCloud")
            } catch {
                await genericAlert(title: "Error", message: error.localizedDescription)
            }
            eraseAlliCloudDataButton.isEnabled = true
            syncSwitch.isEnabled = true
        }
    }
}
