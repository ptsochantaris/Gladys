//
//  AppDelegate.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 16/06/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CoreSpotlight

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?

	func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
		if let c = url.host, c == "in-app-purchase", let p = url.pathComponents.last, let t = Int(p) {
			ViewController.shared.displayIAPRequest(newTotal: t)
			return true
		} else if let c = url.host, c == "paste-clipboard" {
			ViewController.shared.dismissAnyPopOver()
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			let titleParameter = components?.queryItems?.first { $0.name == "title" || $0.name == "label" }
			let noteParameter = components?.queryItems?.first { $0.name == "note" }
			let labelsList = components?.queryItems?.first { $0.name == "labels" }?.value?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
			let importOverrides = ImportOverrides(title: titleParameter?.value, note: noteParameter?.value, labels: labelsList)
			ViewController.shared.pasteClipboard(overrides: importOverrides)
			return true
		}
		return false
	}

	func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {

		if userActivity.activityType == CSSearchableItemActionType {
			if let itemIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
				ViewController.shared.highlightItem(with: itemIdentifier, andOpen: false)
			}
			return true
		}

		if userActivity.activityType == CSQueryContinuationActionType {
			if let searchQuery = userActivity.userInfo?[CSSearchQueryString] as? String {
				ViewController.shared.startSearch(initialText: searchQuery)
			}
			return true
		}

		return false
	}

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool {
		UIApplication.shared.applicationIconBadgeNumber = 0
		PersistedOptions.migrateBrokenDefaults()
		Model.reloadDataIfNeeded()
		if CloudManager.syncSwitchedOn {
			UIApplication.shared.registerForRemoteNotifications()
		}
		log("Initial reachability status: \(reachability.status.name)")
		return true
	}

	func applicationWillEnterForeground(_ application: UIApplication) {
		CloudManager.opportunisticSyncIfNeeded(isStartup: false)
	}

	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		log("Registered for remote notifications")
	}

	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		log("Failed to register for remote notifications")
	}

	func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		CloudManager.received(notificationInfo: userInfo, fetchCompletionHandler: completionHandler)
	}

	func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
		ViewController.executeOrQueue {
			if shortcutItem.type.hasSuffix(".Search") {
				ViewController.shared.forceStartSearch()
			} else if shortcutItem.type.hasSuffix(".Paste") {
				ViewController.shared.forcePaste()
			}
			completionHandler(true)
		}
	}
}

