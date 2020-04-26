//
//  AppDelegate.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa
import CoreSpotlight
import GladysFramework
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
				guard let w = ViewController.shared.view.window else { return }
				if NSApp.isActive, w.isVisible {
					w.orderOut(nil)
				} else {
					NSApp.activate(ignoringOtherApps: true)
					w.makeKeyAndOrderFront(nil)
				}
			}
			hotKey = h
		}
	}

	private var statusItem: NSStatusItem?

	@IBOutlet private weak var infiniteModeMenuEntry: NSMenuItem!

	@IBOutlet private weak var gladysMenuItem: NSMenuItem!
	@IBOutlet private weak var fileMenuItem: NSMenuItem!
	@IBOutlet private weak var editMenuItem: NSMenuItem!
	@IBOutlet private weak var itemMenuItem: NSMenuItem!
	@IBOutlet private weak var windowMenuItem: NSMenuItem!
	@IBOutlet private weak var helpMenuItem: NSMenuItem!

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
		if NSApp.isActive && (ViewController.shared.view.window?.isVisible ?? false) {
			statusItem?.popUpMenu(menu)
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
				s.image = #imageLiteral(resourceName: "menubarIcon")
				statusItem = s
				log("Creating menubar status item")
			}

			if showing {
				if s.menu == nil || forceUpdateMenu {
					s.action = nil
					s.menu = menu
					log("Updating status item menu")
				}
			} else {
				if s.action == nil {
					s.menu = nil
					s.action = #selector(statusBarItemSelected)
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
			a.beginSheetModal(for: ViewController.shared.view.window!) { response in
				switch response.rawValue {
				case 1000:
					log("Cancelled")
				default:
					let url = URL(fileURLWithPath: name)
					self.proceedWithImport(from: url)
				}
			}
		} else {
			ViewController.shared.importFiles(paths: filenames)
		}
	}

	final class ServicesProvider: NSObject {
		var urlEventBeforeLaunch = false

		@objc func handleServices(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
			ViewController.shared.addItems(from: pboard, at: IndexPath(item: 0, section: 0), overrides: nil)
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

	func applicationWillFinishLaunching(_ notification: Notification) {

		AppDelegate.shared = self

		migrateDefaults()
		
		LauncherCommon.killHelper()

		if !receiptExists {
			exit(173)
		}

		CallbackSupport.setupCallbackSupport()

		let s = NSAppleEventManager.shared()
		s.setEventHandler(servicesProvider,
						  andSelector: #selector(ServicesProvider.handleURLEvent(event:replyEvent:)),
						  forEventClass: AEEventClass(kInternetEventClass),
						  andEventID: AEEventID(kAEGetURL))

		PullState.checkMigrations()
		if CloudManager.syncSwitchedOn {
			NSApplication.shared.registerForRemoteNotifications(matching: [])
		}

		IAPManager.shared.start()
		NotificationCenter.default.addObserver(self, selector: #selector(iapChanged), name: .IAPModeChanged, object: nil)
		infiniteModeMenuEntry.isHidden = infiniteMode

		NSApplication.shared.servicesProvider = servicesProvider

		setupSortMenu()
	}
    
	func applicationDidFinishLaunching(_ notification: Notification) {
		AppDelegate.updateHotkey()

		let wn = NSWorkspace.shared.notificationCenter
		wn.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)

		let isShowing = ViewController.shared.view.window?.isVisible ?? false
		updateMenubarIconMode(showing: isShowing, forceUpdateMenu: false)

        NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = true
        
        Model.detectExternalChanges()
		Model.startMonitoringForExternalChangesToBlobs()
	}

	func applicationDidBecomeActive(_ notification: Notification) {
		let isShowing = ViewController.shared.view.window?.isVisible ?? false
		updateMenubarIconMode(showing: isShowing, forceUpdateMenu: false)
        ViewController.shared.showOnActiveIfNeeded()
	}

	func applicationDidResignActive(_ notification: Notification) {
		updateMenubarIconMode(showing: false, forceUpdateMenu: false)
		Model.trimTemporaryDirectory()
        ViewController.shared.hideOnInactiveIfNeeded()
	}

	@objc private func systemDidWake() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
			AppDelegate.updateHotkey()
			CloudManager.opportunisticSyncIfNeeded()
		}
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		IAPManager.shared.stop()
	}

	func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
		CloudManager.received(notificationInfo: userInfo)
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		NSApplication.shared.windows.first(where: { $0.contentViewController is ViewController })?.makeKeyAndOrderFront(self)
		return false
	}

	func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
		return false
	}

	private func focus() {
		NSApp.activate(ignoringOtherApps: true)
		ViewController.shared.view.window?.makeKeyAndOrderFront(nil)
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
				ViewController.shared.startSearch(initialText: searchQuery)
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
		clearCaches()
	}

	@IBAction private func aboutSelected(_ sender: NSMenuItem) {
		let p = NSMutableParagraphStyle()
		p.alignment = .center
		p.lineSpacing = 1
		let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
		let credits = NSAttributedString(string: "If you would like to report a bug or have any issues or suggestions, please email me at paul@bru.build\n", attributes: [
			.font: font,
			.foregroundColor: NSColor.controlTextColor,
			.paragraphStyle: p
			])

		let windowsBefore = NSApplication.shared.windows
		NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])

		if PersistedOptions.alwaysOnTop {
			var windowsAfter = NSApplication.shared.windows
			for b in windowsBefore {
				if let i = windowsAfter.firstIndex(of: b) {
					windowsAfter.remove(at: i)
				}
			}
			let aboutWindow = windowsAfter.first
			aboutWindow?.level = .modalPanel
		}
	}

	@objc private func iapChanged() {
		infiniteModeMenuEntry.isHidden = infiniteMode
		updateMenubarIconMode(showing: true, forceUpdateMenu: true)
	}

	@IBAction private func infiniteModeSelected(_ sender: NSMenuItem) {
		IAPManager.shared.displayRequest(newTotal: -1)
	}

	@IBAction private func openWebSite(_ sender: NSMenuItem) {
		NSWorkspace.shared.open(URL(string: "https://www.bru.build/gladys-for-macos")!)
	}

	/////////////////////////////////////////////////////////////////

	@IBAction private func importSelected(_ sender: NSMenuItem) {

		let w = ViewController.shared.view.window!
		if !w.isVisible {
			w.makeKeyAndOrderFront(nil)
		}

		let o = NSOpenPanel()
		o.title = "Import Archive…"
		o.prompt = "Import"
		o.message = "Select an archive from which to\nmerge items into your existing collection."
		o.isExtensionHidden = true
		o.allowedFileTypes = ["gladysArchive"]
		o.beginSheetModal(for: w) { [weak self] response in
			if response == .OK, let url = o.url {
				DispatchQueue.main.async {
					self?.proceedWithImport(from: url)
				}
			}
		}
	}

	private func proceedWithImport(from url: URL) {
		ViewController.shared.startProgress(for: nil, titleOverride: "Importing items from archive, this can take a moment…")
		DispatchQueue.main.async { // give UI a chance to update
			do {
				try Model.importArchive(from: url, removingOriginal: false)
				ViewController.shared.endProgress()
			} catch {
				ViewController.shared.endProgress()
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
			a.beginSheetModal(for: ViewController.shared.view.window!, completionHandler: nil)
		}
	}

	@IBAction private func exportSelected(_ sender: NSMenuItem) {

		let w = ViewController.shared.view.window!
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
		s.beginSheetModal(for: w) { response in
			if response == .OK, let selectedUrl = s.url {
                let p = Model.createArchive(using: Model.sharedFilter) { createdUrl, error in
					self.createOperationDone(selectedUrl: selectedUrl, createdUrl: createdUrl, error: error)
				}
				ViewController.shared.startProgress(for: p)
			}
		}
	}

	@objc private func onlyVisibleItemsToggled(_ sender: NSButton) {
		PersistedOptions.exportOnlyVisibleItems = sender.integerValue == 1
	}

	@IBAction private func zipSelected(_ sender: NSMenuItem) {

		let w = ViewController.shared.view.window!
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
		s.beginSheetModal(for: w) { response in
			if response == .OK, let selectedUrl = s.url {
				assert(Thread.isMainThread)
                let p = Model.createZip(using: Model.sharedFilter) { createdUrl, error in
					self.createOperationDone(selectedUrl: selectedUrl, createdUrl: createdUrl, error: error)
				}
				ViewController.shared.startProgress(for: p)
			}
		}
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {

		if (menuItem.parent?.title ?? "").hasPrefix("Sort ") {
			return !Model.drops.isEmpty
		}

		switch menuItem.action {
		case #selector(importSelected(_:)), #selector(exportSelected(_:)), #selector(zipSelected(_:)):
			return !ViewController.shared.isDisplayingProgress
		case #selector(showMain(_:)):
			if let w = ViewController.shared.view.window {
				menuItem.title = w.title
				menuItem.isHidden = w.isVisible && statusItem == nil
			}
			return !menuItem.isHidden
		default:
			return true
		}
	}

	@objc private func showMain(_ sender: Any?) {
		if let w = ViewController.shared.view.window {
			w.makeKeyAndOrderFront(nil)
		}
	}

	private func createOperationDone(selectedUrl: URL, createdUrl: URL?, error: Error?) {
		// thread
		DispatchQueue.main.async {
			ViewController.shared.endProgress()
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

	@IBOutlet weak var sortAscendingMenu: NSMenu!
	@IBOutlet weak var sortDescendingMenu: NSMenu!

	private func setupSortMenu() {
		for sortOption in Model.SortOption.options {
			sortAscendingMenu.addItem(withTitle: sortOption.ascendingTitle, action: #selector(sortOptionSelected(_:)), keyEquivalent: "")
			sortDescendingMenu.addItem(withTitle: sortOption.descendingTitle, action: #selector(sortOptionSelected(_:)), keyEquivalent: "")
		}
	}

	@objc private func sortOptionSelected(_ sender: NSMenu) {
        let selectedItems = ContiguousArray(ViewController.shared.selectedItems)
		if selectedItems.count < 2 {
			proceedWithSort(sender: sender, items: [])
		} else {
			let a = NSAlert()
			a.messageText = "Sort selected items?"
			a.informativeText = "You have selected a range of items. Would you like to sort just the selected items, or sort all the items in your collection?"
			a.addButton(withTitle: "Sort Selected")
			a.addButton(withTitle: "Sort All")
			a.addButton(withTitle: "Cancel")
			a.beginSheetModal(for: ViewController.shared.view.window!) { response in
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
