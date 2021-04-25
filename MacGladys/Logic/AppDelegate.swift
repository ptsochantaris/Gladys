//
//  AppDelegate.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa
import CoreSpotlight
import HotKey
import CloudKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

	static private var hotKey: HotKey?

	static func updateHotkey() {
		hotKey = nil

		let hotKeyCode = PersistedOptions.hotkeyChar
		let enable = hotKeyCode >= 0 && (PersistedOptions.hotkeyCmd || PersistedOptions.hotkeyOption || PersistedOptions.hotkeyCtrl)
		if enable {
			var modifiers = NSEvent.ModifierFlags()
			if PersistedOptions.hotkeyOption { modifiers = modifiers.union(.option) }
			if PersistedOptions.hotkeyShift { modifiers = modifiers.union(.shift) }
			if PersistedOptions.hotkeyCtrl { modifiers = modifiers.union(.control) }
			if PersistedOptions.hotkeyCmd { modifiers = modifiers.union(.command) }
			let h = HotKey(carbonKeyCode: UInt32(hotKeyCode), carbonModifiers: modifiers.carbonFlags)
			h.keyDownHandler = {
                guard let w = NSApp.windows.first else { return }
				if NSApp.isActive, w.isVisible {
                    NSApp.orderedWindows.forEach {
                        $0.hide()
                    }
				} else {
					NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderedWindows.forEach {
                        $0.makeKeyAndOrderFront(nil)
                    }
				}
			}
			hotKey = h
		}
	}

	private var statusItem: NSStatusItem?

	@IBOutlet private var gladysMenuItem: NSMenuItem!
	@IBOutlet private var fileMenuItem: NSMenuItem!
	@IBOutlet private var editMenuItem: NSMenuItem!
	@IBOutlet private var itemMenuItem: NSMenuItem!
	@IBOutlet private var windowMenuItem: NSMenuItem!
	@IBOutlet private var helpMenuItem: NSMenuItem!

	private var menu: NSMenu {
		let m = NSMenu(title: "Gladys")
		m.addItem(gladysMenuItem.copy() as! NSMenuItem)
		m.addItem(fileMenuItem.copy() as! NSMenuItem)
		m.addItem(editMenuItem.copy() as! NSMenuItem)
		m.addItem(itemMenuItem.copy() as! NSMenuItem)
		m.addItem(windowMenuItem.copy() as! NSMenuItem)
		m.addItem(helpMenuItem.copy() as! NSMenuItem)
		return m
	}

	@objc private func statusBarItemSelected() {
		if NSApp.isActive && (keyGladysControllerIfExists?.view.window?.isVisible ?? false) {
            statusItem?.menu?.popUp(positioning: nil, at: .zero, in: nil)
		} else {
			focus()
		}
	}

	func updateMenubarIconMode(showing: Bool, forceUpdateMenu: Bool) {
		if PersistedOptions.menubarIconMode {

			if NSApp.activationPolicy() != .accessory {
				log("Changing activation policy to accessory mode")
				NSApp.setActivationPolicy(.accessory)
				DispatchQueue.main.async {
					NSApp.activate(ignoringOtherApps: true)
					NSMenu.setMenuBarVisible(true)
				}
			}

			let s: NSStatusItem
			if let existingStatusItem = statusItem {
				s = existingStatusItem
			} else {
				s = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                s.button?.image = #imageLiteral(resourceName: "menubarIcon")
				statusItem = s
				log("Creating menubar status item")
			}

			if showing {
				if s.menu == nil || forceUpdateMenu {
                    s.button?.action = nil
					s.menu = menu
					log("Updating status item menu")
				}
			} else {
                if s.button?.action == nil {
					s.menu = nil
                    s.button?.action = #selector(statusBarItemSelected)
					log("Status item watching for click")
				}
			}

		} else if NSApp.activationPolicy() != .regular {
			log("Changing activation policy to regular mode")
			NSApp.setActivationPolicy(.regular)
			if let s = statusItem {
				log("Clearing status item")
				NSStatusBar.system.removeStatusItem(s)
				statusItem = nil
			}
			DispatchQueue.main.async {
				NSApp.activate(ignoringOtherApps: true)
				NSMenu.setMenuBarVisible(true)
			}
		}
	}

	func application(_ sender: NSApplication, openFiles filenames: [String]) {
		if filenames.count == 1, let name = filenames.first, name.hasSuffix(".gladysArchive") == true {
			let a = NSAlert()
			a.messageText = "Import items from this archive?"
			a.informativeText = "This is an archive of Gladys items that was previously exported. Would you like to import the items inside this archive to your current collection?"
			a.addButton(withTitle: "Cancel")
			a.addButton(withTitle: "Import Items")
            let response = a.runModal()
            switch response.rawValue {
            case 1000:
                log("Cancelled")
            default:
                let url = URL(fileURLWithPath: name)
                self.proceedWithImport(from: url)
            }
		} else {
            Model.importFiles(paths: filenames, filterContext: keyGladysControllerIfExists?.filter)
		}
	}

	final class ServicesProvider: NSObject {
		var urlEventBeforeLaunch = false

		@objc func handleServices(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
			Model.addItems(from: pboard, at: IndexPath(item: 0, section: 0), overrides: nil, filterContext: nil)
		}

		@objc func handleURLEvent(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
            if PersistedOptions.blockGladysUrlRequests { return }
			if let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: urlString) {
				urlEventBeforeLaunch = true
				CallbackSupport.handlePossibleCallbackURL(url: url)
			}
		}
	}

	private let servicesProvider = ServicesProvider()
	static var shared: AppDelegate?

	private func migrateDefaults() {
		if PersistedOptions.defaultsVersion < 1 {
			if PersistedOptions.launchAtLogin {
				PersistedOptions.launchAtLogin = true
			}
			PersistedOptions.defaultsVersion = 1
		}
	}
    
    @IBAction private func newWindowSelected(_ sender: Any?) {
        let controller = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("windowController")) as! WindowController
        if let w = controller.window {
            if PersistedOptions.autoShowFromEdge > 0 {
                w.gladysController?.showWindow(window: w, wasAuto: true)
            } else {
                w.makeKeyAndOrderFront(sender)
            }
        }
    }
    
    override init() {
        super.init()

        AppDelegate.shared = self

        migrateDefaults()
        
        LauncherCommon.killHelper()

        Model.setup()
        
        CallbackSupport.setupCallbackSupport()

        PullState.checkMigrations()
    }
                
	func applicationWillFinishLaunching(_ notification: Notification) {

        let s = NSAppleEventManager.shared()
        s.setEventHandler(servicesProvider,
                          andSelector: #selector(ServicesProvider.handleURLEvent(event:replyEvent:)),
                          forEventClass: AEEventClass(kInternetEventClass),
                          andEventID: AEEventID(kAEGetURL))

        NSApplication.shared.servicesProvider = servicesProvider

        for sortOption in Model.SortOption.options {
            sortAscendingMenu.addItem(withTitle: sortOption.ascendingTitle, action: #selector(sortOptionSelected(_:)), keyEquivalent: "")
            sortDescendingMenu.addItem(withTitle: sortOption.descendingTitle, action: #selector(sortOptionSelected(_:)), keyEquivalent: "")
        }

        if PersistedOptions.badgeIconWithItemCount {
            Model.updateBadge()
        }
        
        if CloudManager.syncSwitchedOn {
            NSApplication.shared.registerForRemoteNotifications(matching: [])
            CloudManager.sync { _ in }
        }

        setupClipboardSnooping()
        
        NotificationCenter.default.addObserver(self, selector: #selector(setupClipboardSnooping), name: .ClipboardSnoopingChanged, object: nil)
        
        DistributedNotificationCenter.default.addObserver(self, selector: #selector(interfaceModeChanged(sender:)), name: NSNotification.Name(rawValue: "AppleInterfaceThemeChangedNotification"), object: nil)
	}
        
    @objc private func interfaceModeChanged(sender: NSNotification) {
        imageCache.removeAllObjects()
        NotificationCenter.default.post(name: .ItemCollectionNeedsDisplay, object: nil)
    }
    
	func applicationDidFinishLaunching(_ notification: Notification) {
		AppDelegate.updateHotkey()

		let wn = NSWorkspace.shared.notificationCenter
		wn.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)

		let isShowing = keyGladysControllerIfExists?.view.window?.isVisible ?? false
		updateMenubarIconMode(showing: isShowing, forceUpdateMenu: false)

        NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = true
        
        Model.detectExternalChanges()
		Model.startMonitoringForExternalChangesToBlobs()
        
        restoreWindows()
	}
    
    private func showAll() {
        NSApp.windows.forEach {
            $0.gladysController?.showWindow(window: $0, wasAuto: PersistedOptions.autoShowFromEdge > 0)
        }
        updateMenubarIconMode(showing: true, forceUpdateMenu: false)
    }
    
	func applicationDidBecomeActive(_ notification: Notification) {
        showAll()
	}

	func applicationDidResignActive(_ notification: Notification) {
		updateMenubarIconMode(showing: false, forceUpdateMenu: false)
		Model.trimTemporaryDirectory()
        if PersistedOptions.autoShowWhenDragging || PersistedOptions.autoShowFromEdge > 0 {
            NSApp.windows.forEach {
                $0.gladysController?.hideWindowBecauseOfMouse(window: $0)
            }
        }
	}

	@objc private func systemDidWake() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
			AppDelegate.updateHotkey()
			CloudManager.opportunisticSyncIfNeeded()
		}
	}

	func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
		CloudManager.received(notificationInfo: userInfo)
	}
    
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showAll()
		return false
	}

	func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
		return false
	}

	private func focus() {
		NSApp.activate(ignoringOtherApps: true)
        keyGladysControllerIfExists?.view.window?.makeKeyAndOrderFront(nil)
	}

	func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {

		if userActivity.activityType == CSSearchableItemActionType {
			if let itemIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
				focus()
                let request = HighlightRequest(uuid: itemIdentifier, open: true)
                NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
			}
			return true

		} else if userActivity.activityType == CSQueryContinuationActionType {
			if let searchQuery = userActivity.userInfo?[CSSearchQueryString] as? String {
				focus()
                keyGladysControllerIfExists?.startSearch(initialText: searchQuery)
			}
			return true

		} else if userActivity.activityType == kGladysDetailViewingActivity {
			if let uuid = userActivity.userInfo?[kGladysDetailViewingActivityItemUuid] as? UUID {
				focus()
                let request = HighlightRequest(uuid: uuid.uuidString, open: true)
                NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
			} else if let uuidString = userActivity.userInfo?[kGladysDetailViewingActivityItemUuid] as? String {
				focus()
                let request = HighlightRequest(uuid: uuidString, open: true)
                NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
			}
			return true
			
		} else if userActivity.activityType == kGladysQuicklookActivity {
			if let userInfo = userActivity.userInfo, let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String {
				focus()
				let childUuid = userInfo[kGladysDetailViewingActivityItemTypeUuid] as? String
                let request = HighlightRequest(uuid: uuidString, preview: true, focusOnChildUuid: childUuid)
                NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
			}
			return true
		}

		return false
	}

	func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		log("APNS ready: \(deviceToken.base64EncodedString())")
		CloudManager.apnsUpdate(deviceToken)
	}

	func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		log("Warning: APNS registration failed: \(error.finalDescription)")
		CloudManager.apnsUpdate(nil)
	}

	func applicationWillResignActive(_ notification: Notification) {
        Model.clearCaches()
	}
    
    func applicationWillTerminate(_ notification: Notification) {
        storeWindowStates()
    }
    
    func applicationWillHide(_ notification: Notification) {
        storeWindowStates()
    }

	@IBAction private func aboutSelected(_ sender: NSMenuItem) {
        keyGladysControllerIfExists?.performSegue(withIdentifier: "showAbout", sender: nil)
	}

	@IBAction private func openWebSite(_ sender: Any) {
		NSWorkspace.shared.open(URL(string: "https://www.bru.build/gladys-for-macos")!)
	}

	/////////////////////////////////////////////////////////////////

    private var pasteboardObservationTimer: Timer?
    private var pasteboardObservationCount = NSPasteboard.general.changeCount

    @objc private func setupClipboardSnooping() {
        let snoop = PersistedOptions.clipboardSnooping
        
        if snoop, pasteboardObservationTimer == nil {
            let pasteboard = NSPasteboard.general
            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                let newCount = pasteboard.changeCount
                guard let s = self, s.pasteboardObservationCount != newCount else {
                    return
                }
                s.pasteboardObservationCount = newCount
                if let text = pasteboard.string(forType: .string), (PersistedOptions.clipboardSnoopingAll || !pasteboard.typesAreSensitive) {
                    let i = NSItemProvider(object: text as NSItemProviderWriting)
                    Model.addItems(itemProviders: [i], indexPath: IndexPath(item: 0, section: 0), overrides: nil, filterContext: keyGladysControllerIfExists?.filter)
                }
            }
            timer.tolerance = 0.5
            pasteboardObservationTimer = timer

        } else if !snoop, let p = pasteboardObservationTimer {
            p.invalidate()
            pasteboardObservationTimer = nil
        }
    }
    
	@IBAction private func importSelected(_ sender: NSMenuItem) {

        guard let controller = keyGladysControllerIfExists, let w = controller.view.window else { return }

		if !w.isVisible {
			w.makeKeyAndOrderFront(nil)
		}

		let o = NSOpenPanel()
		o.title = "Import Archive…"
		o.prompt = "Import"
		o.message = "Select an archive from which to\nmerge items into your existing collection."
		o.isExtensionHidden = true
		o.allowedFileTypes = ["gladysArchive"]
        let response = o.runModal()
        if response == .OK, let url = o.url {
            proceedWithImport(from: url)
        }
	}

	private func proceedWithImport(from url: URL) {
        keyGladysControllerIfExists?.startProgress(for: nil, titleOverride: "Importing items from archive, this can take a moment…")
		DispatchQueue.main.async { // give UI a chance to update
			do {
				try Model.importArchive(from: url, removingOriginal: false)
                keyGladysControllerIfExists?.endProgress()
			} catch {
                keyGladysControllerIfExists?.endProgress()
				self.alertOnMainThread(error: error)
			}
		}
	}

	private func alertOnMainThread(error: Error) {
		DispatchQueue.main.async {
			let a = NSAlert()
			a.alertStyle = .warning
			a.messageText = "Operation Failed"
			a.informativeText = error.finalDescription
            a.runModal()
		}
	}

	@IBAction private func exportSelected(_ sender: NSMenuItem) {

        guard let controller = keyGladysControllerIfExists, let w = controller.view.window else { return }
        
		if !w.isVisible {
			w.makeKeyAndOrderFront(nil)
		}

		let s = NSSavePanel()
		s.title = "Export Archive…"
		s.prompt = "Export"
		s.message = "Export your colection for importing\nto other devices, or as backup."
		s.isExtensionHidden = true
		s.nameFieldStringValue = "Gladys Archive"
		s.allowedFileTypes = ["gladysArchive"]
        let response = s.runModal()
        if response == .OK, let selectedUrl = s.url {
            let p = Model.createArchive(using: controller.filter) { createdUrl, error in
                self.createOperationDone(selectedUrl: selectedUrl, createdUrl: createdUrl, error: error)
            }
            keyGladysControllerIfExists?.startProgress(for: p)
        }
	}

	@objc private func onlyVisibleItemsToggled(_ sender: NSButton) {
		PersistedOptions.exportOnlyVisibleItems = sender.integerValue == 1
	}

	@IBAction private func zipSelected(_ sender: NSMenuItem) {

        guard let controller = keyGladysControllerIfExists else { return }
		let w = controller.view.window!
		if !w.isVisible {
			w.makeKeyAndOrderFront(nil)
		}

		let optionView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 44))
		let selectItemsOnlyOption = NSButton(checkboxWithTitle: "Add only visible items", target: self, action: #selector(onlyVisibleItemsToggled(_:)))
		selectItemsOnlyOption.integerValue = PersistedOptions.exportOnlyVisibleItems ? 1 : 0
		selectItemsOnlyOption.frame = optionView.bounds
		optionView.addSubview(selectItemsOnlyOption)

		let s = NSSavePanel()
		s.accessoryView = optionView
		s.title = "Create ZIP…"
		s.prompt = "Create ZIP"
		s.message = "Create a ZIP file of the current collection."
		s.isExtensionHidden = true
		s.nameFieldStringValue = "Gladys"
		s.allowedFileTypes = [kUTTypeZipArchive as String]
        let response = s.runModal()
        if response == .OK, let selectedUrl = s.url {
            assert(Thread.isMainThread)
            let p = Model.createZip(using: controller.filter) { createdUrl, error in
                self.createOperationDone(selectedUrl: selectedUrl, createdUrl: createdUrl, error: error)
            }
            keyGladysControllerIfExists?.startProgress(for: p)
        }
	}
    
    @objc func showPreferences(_ sender: Any?) {
        let controller = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "preferences") as! NSWindowController
        if let w = controller.window {
            w.makeKeyAndOrderFront(sender)
        }
    }

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {

        if menuItem.action == #selector(newWindowSelected(_:)) {
            return true
        }

        if menuItem.action == #selector(showPreferences(_:)) {
            return true
        }

        guard let controller = keyGladysControllerIfExists else { return false }

		if (menuItem.parent?.title ?? "").hasPrefix("Sort ") {
			return !Model.drops.isEmpty
		}
        
		switch menuItem.action {
		case #selector(importSelected(_:)), #selector(exportSelected(_:)), #selector(zipSelected(_:)):
			return !controller.isDisplayingProgress
		case #selector(showMain(_:)):
			if let w = controller.view.window {
				menuItem.title = w.title
				menuItem.isHidden = w.isVisible && statusItem == nil
			}
			return !menuItem.isHidden
		default:
			return true
		}
	}

	@objc private func showMain(_ sender: Any?) {
        if let w = keyGladysControllerIfExists?.view.window {
			w.makeKeyAndOrderFront(nil)
		}
	}

	private func createOperationDone(selectedUrl: URL, createdUrl: URL?, error: Error?) {
		// thread
		DispatchQueue.main.async {
            keyGladysControllerIfExists?.endProgress()
		}

		guard let createdUrl = createdUrl else {
			if let error = error {
				self.alertOnMainThread(error: error)
			}
			return
		}

		do {
			let fm = FileManager.default
			try fm.moveAndReplaceItem(at: createdUrl, to: selectedUrl)
			try fm.setAttributes([FileAttributeKey.extensionHidden: true], ofItemAtPath: selectedUrl.path)
			NSWorkspace.shared.activateFileViewerSelecting([selectedUrl])
		} catch {
			self.alertOnMainThread(error: error)
		}
	}

	func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
		CloudManager.acceptShare(metadata)
	}

	////////////////////////////////////////////// Sorting

	@IBOutlet var sortAscendingMenu: NSMenu!
	@IBOutlet var sortDescendingMenu: NSMenu!

	@objc private func sortOptionSelected(_ sender: NSMenu) {
        guard let controller = keyGladysControllerIfExists else { return }
        let selectedItems = ContiguousArray(controller.selectedItems)
		if selectedItems.count < 2 {
			proceedWithSort(sender: sender, items: [])
		} else {
			let a = NSAlert()
			a.messageText = "Sort selected items?"
			a.informativeText = "You have selected a range of items. Would you like to sort just the selected items, or sort all the items in your collection?"
			a.addButton(withTitle: "Sort Selected")
			a.addButton(withTitle: "Sort All")
			a.addButton(withTitle: "Cancel")
            let response = a.runModal()
            switch response.rawValue {
            case 1000:
                self.proceedWithSort(sender: sender, items: selectedItems)
            case 1001:
                self.proceedWithSort(sender: sender, items: [])
            default:
                break
            }
		}
	}

	private func proceedWithSort(sender: NSMenu, items: ContiguousArray<ArchivedItem>) {
		if let sortOption = Model.SortOption.options.first(where: { $0.ascendingTitle == sender.title }) {
			let sortMethod = sortOption.handlerForSort(itemsToSort: items, ascending: true)
			sortMethod()
		} else if let sortOption = Model.SortOption.options.first(where: { $0.descendingTitle == sender.title }) {
			let sortMethod = sortOption.handlerForSort(itemsToSort: items, ascending: false)
			sortMethod()
		}
	}
}
