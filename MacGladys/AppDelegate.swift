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
						w.close()
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
			NSApplication.shared.registerForRemoteNotifications(matching: [.badge])
		}

		IAPManager.shared.start()
		NotificationCenter.default.addObserver(self, selector: #selector(iapChanged), name: .IAPModeChanged, object: nil)
		infiniteModeMenuEntry.isHidden = infiniteMode

		AppDelegate.updateHotkey()

		NSApplication.shared.servicesProvider = servicesProvider
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

	/*func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		Model.saveIsDueToSyncFetch = true
		Model.queueNextSaveCallback {
			NSApplication.shared.reply(toApplicationShouldTerminate: true)
		}
		Model.save()
		return NSApplication.TerminateReply.terminateLater
	}*/


}

