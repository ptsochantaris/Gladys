//
//  AppDelegate.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa
import CoreSpotlight

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		if CloudManager.syncSwitchedOn {
			NSApplication.shared.registerForRemoteNotifications(matching: [.badge])
		}
		IAPManager.shared.start()
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

	/*func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		Model.saveIsDueToSyncFetch = true
		Model.queueNextSaveCallback {
			NSApplication.shared.reply(toApplicationShouldTerminate: true)
		}
		Model.save()
		return NSApplication.TerminateReply.terminateLater
	}*/
}

