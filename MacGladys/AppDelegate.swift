//
//  AppDelegate.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa
import CoreSpotlight
import MacGladysFramework
import HotKey
import CloudKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

	static private var hotKey: HotKey?

	static func updateHotkey() {
		let hotKeyCode = PersistedOptions.hotkeyChar
		let enable = hotKeyCode >= 0 && (PersistedOptions.hotkeyCmd || PersistedOptions.hotkeyOption || PersistedOptions.hotkeyCtrl)
		if enable {
			var modifiers = NSEvent.ModifierFlags()
			if PersistedOptions.hotkeyOption { modifiers = modifiers.union(.option) }
			if PersistedOptions.hotkeyShift { modifiers = modifiers.union(.shift) }
			if PersistedOptions.hotkeyCtrl { modifiers = modifiers.union(.control) }
			if PersistedOptions.hotkeyCmd { modifiers = modifiers.union(.command) }
			hotKey = HotKey(carbonKeyCode: UInt32(hotKeyCode), carbonModifiers: modifiers.carbonFlags)
			hotKey?.keyDownHandler = {
				if let w = ViewController.shared.view.window {
					if w.isVisible {
						w.orderOut(nil)
					} else {
						w.makeKeyAndOrderFront(nil)
					}
				}
			}
		} else {
			hotKey = nil
		}
	}

	func application(_ sender: NSApplication, openFiles filenames: [String]) {
		ViewController.shared.importFiles(paths: filenames)
	}

	class ServicesProvider: NSObject {
		var urlEventBeforeLaunch = false

		@objc func handleServices(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
			ViewController.shared.addItems(from: pboard, at: IndexPath(item: 0, section: 0), overrides: nil)
		}

		@objc func handleURLEvent(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
			if let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: urlString) {
				urlEventBeforeLaunch = true
				CallbackSupport.handlePossibleCallbackURL(url: url)
			}
		}
	}

	private let servicesProvider = ServicesProvider()

	func applicationWillFinishLaunching(_ notification: Notification) {

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

		if CloudManager.syncSwitchedOn {
			NSApplication.shared.registerForRemoteNotifications(matching: [])
		}

		IAPManager.shared.start()
		NotificationCenter.default.addObserver(self, selector: #selector(iapChanged), name: .IAPModeChanged, object: nil)
		infiniteModeMenuEntry.isHidden = infiniteMode

		NSApplication.shared.servicesProvider = servicesProvider
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		AppDelegate.updateHotkey()
		CloudManager.checkMigrations()
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		IAPManager.shared.stop()
	}

	func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
		CloudManager.received(notificationInfo: userInfo)
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		NSApplication.shared.windows.first(where: { $0.contentViewController is ViewController })?.makeKeyAndOrderFront(self)
		return false
	}

	func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
		return false
	}

	func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
		if userActivity.activityType == CSSearchableItemActionType {
			if let itemIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
				ViewController.shared.highlightItem(with: itemIdentifier, andOpen: false)
			}
			return true

		} else if userActivity.activityType == CSQueryContinuationActionType {
			if let searchQuery = userActivity.userInfo?[CSSearchQueryString] as? String {
				ViewController.shared.startSearch(initialText: searchQuery)
			}
			return true

		} else if userActivity.activityType == kGladysDetailViewingActivity {
			if let itemIdentifier = userActivity.userInfo?[kGladysDetailViewingActivityItemUuid] as? UUID {
				ViewController.shared.highlightItem(with: itemIdentifier.uuidString, andOpen: true)
			}
			return true
		}

		return false
	}

	@IBAction func aboutSelected(_ sender: NSMenuItem) {
		let p = NSMutableParagraphStyle()
		p.alignment = .center
		p.lineSpacing = 1
		let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
		let credits = NSAttributedString(string: "If you would like to report a bug or have any issues or suggestions, please email me at paul@bru.build\n", attributes: [
			NSAttributedStringKey.font: font,
			NSAttributedStringKey.paragraphStyle: p,
			])
		NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
	}

	@IBOutlet weak var infiniteModeMenuEntry: NSMenuItem!
	@objc private func iapChanged() {
		infiniteModeMenuEntry.isHidden = infiniteMode
	}

	@IBAction func infiniteModeSelected(_ sender: NSMenuItem) {
		IAPManager.shared.displayRequest(newTotal: -1)
	}

	@IBAction func openWebSite(_ sender: NSMenuItem) {
		NSWorkspace.shared.open(URL(string: "https://www.bru.build/gladys-for-macos")!)
	}

	/////////////////////////////////////////////////////////////////

	@IBAction func importSelected(_ sender: NSMenuItem) {

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
		o.beginSheetModal(for: w) { response in
			if response == .OK, let url = o.url {
				DispatchQueue.main.async {
					do {
						try Model.importData(from: url, removingOriginal: false)
					} catch {
						self.alertOnMainThread(error: error)
					}
				}
			}
		}
	}

	private func alertOnMainThread(error: Error) {
		DispatchQueue.main.async {
			let a = NSAlert(error: error)
			a.beginSheetModal(for: ViewController.shared.view.window!, completionHandler: nil)
		}
	}

	@IBAction func exportSelected(_ sender: NSMenuItem) {

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
				let p = Model.createArchive { createdUrl, error in
					self.createOperationDone(selectedUrl: selectedUrl, createdUrl: createdUrl, error: error)
				}
				ViewController.shared.startProgress(for: p)
			}
		}
	}

	@objc private func onlyVisibleItemsToggled(_ sender: NSButton) {
		PersistedOptions.exportOnlyVisibleItems = sender.integerValue == 1
	}

	@IBAction func zipSelected(_ sender: NSMenuItem) {

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
				let p = Model.createZip { createdUrl, error in
					self.createOperationDone(selectedUrl: selectedUrl, createdUrl: createdUrl, error: error)
				}
				ViewController.shared.startProgress(for: p)
			}
		}
	}

	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(importSelected(_:)), #selector(exportSelected(_:)), #selector(zipSelected(_:)):
			return !ViewController.shared.isDisplayingProgress
		case #selector(showMain(_:)):
			if let w = ViewController.shared.view.window {
				menuItem.title = w.title
				menuItem.isHidden = w.isVisible
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
			if fm.fileExists(atPath: selectedUrl.path) {
				try fm.removeItem(at: selectedUrl)
			}
			try fm.moveItem(at: createdUrl, to: selectedUrl)
			try fm.setAttributes([FileAttributeKey.extensionHidden: true], ofItemAtPath: selectedUrl.path)
			NSWorkspace.shared.activateFileViewerSelecting([selectedUrl])
		} catch {
			self.alertOnMainThread(error: error)
		}
	}

	func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShareMetadata) {
		CloudManager.acceptShare(metadata)
	}
}
