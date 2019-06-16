//
//  AppDelegate.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 16/06/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CoreSpotlight
import CloudKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?

	func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {

		if let c = url.host, c == "inspect-item", let itemId = url.pathComponents.last {
			ViewController.executeOrQueue {
				ViewController.shared.highlightItem(with: itemId, andOpen: true)
			}

		} else if let c = url.host, c == "in-app-purchase", let p = url.pathComponents.last, let t = Int(p) {
			ViewController.executeOrQueue {
				IAPManager.shared.displayRequest(newTotal: t)
			}

		} else if let c = url.host, c == "paste-clipboard" { // this is legacy
			let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
			let titleParameter = components?.queryItems?.first { $0.name == "title" || $0.name == "label" }
			let noteParameter = components?.queryItems?.first { $0.name == "note" }
			let labelsList = components?.queryItems?.first { $0.name == "labels" }
			ViewController.executeOrQueue {
				CallbackSupport.handlePasteRequest(title: titleParameter?.value, note: noteParameter?.value, labels: labelsList?.value, skipVisibleErrors: false)
			}

		} else if url.host == nil { // just opening
			if url.isFileURL, url.pathExtension.lowercased() == "gladysarchive" {
				let a = UIAlertController(title: "Import Archive?", message: "Import items from \"\(url.deletingPathExtension().lastPathComponent)\"?", preferredStyle: .alert)
				a.addAction(UIAlertAction(title: "Import", style: .destructive) { _ in
					let inPlace = options[.openInPlace] as? Bool ?? false
					var securityScoped = false
					if inPlace {
						securityScoped = url.startAccessingSecurityScopedResource()
					}
					do {
						try Model.importArchive(from: url, removingOriginal: !inPlace)
					} catch {
						genericAlert(title: "Could not import data", message: error.finalDescription)
					}
					if securityScoped {
						url.stopAccessingSecurityScopedResource()
					}
				})
				a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
				ViewController.executeOrQueue {
					ViewController.top.present(a, animated: true)
				}
			}

		} else {
			ViewController.executeOrQueue {
				CallbackSupport.handlePossibleCallbackURL(url: url)
			}
		}

		return true
	}

	func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {

		switch userActivity.activityType {
		case CSSearchableItemActionType:
			if let itemIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
				ViewController.shared.highlightItem(with: itemIdentifier)
			}
			return true

		case CSQueryContinuationActionType:
			if let searchQuery = userActivity.userInfo?[CSSearchQueryString] as? String {
				ViewController.shared.startSearch(initialText: searchQuery)
			}
			return true

		case kGladysDetailViewingActivity:
			if let userInfo = userActivity.userInfo, let uuid = userInfo[kGladysDetailViewingActivityItemUuid] as? UUID { // legacy
				ViewController.shared.highlightItem(with: uuid.uuidString, andOpen: true)
			} else if let userInfo = userActivity.userInfo, let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String {
				ViewController.shared.highlightItem(with: uuidString, andOpen: true)
			}
			return true

		case kGladysQuicklookActivity:
			if let userInfo = userActivity.userInfo, let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String {
				let childUuid = userInfo[kGladysDetailViewingActivityItemTypeUuid] as? String
				ViewController.shared.highlightItem(with: uuidString, andPreview: true, focusOnChild: childUuid)
			}
			return true

		case "PasteClipboardIntent", "CopyItemIntent", "CopyComponentIntent":
			return true

		default:
			return false
		}
	}

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		UIApplication.shared.applicationIconBadgeNumber = 0
		PersistedOptions.migrateBrokenDefaults()
		Model.reloadDataIfNeeded()
		PullState.checkMigrations()
		if CloudManager.syncSwitchedOn {
			UIApplication.shared.registerForRemoteNotifications()
		}
		log("Initial reachability status: \(reachability.status.name)")
		CallbackSupport.setupCallbackSupport()
		IAPManager.shared.start()
		return true
	}

	func applicationWillTerminate(_ application: UIApplication) {
		IAPManager.shared.stop()
	}

	func applicationWillEnterForeground(_ application: UIApplication) {
		CloudManager.opportunisticSyncIfNeeded(isStartup: false)
	}

	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		log("APNS ready: \(deviceToken.base64EncodedString())")
		CloudManager.apnsUpdate(deviceToken)
	}

	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		log("Warning: APNS registration failed: \(error.finalDescription)")
		CloudManager.apnsUpdate(nil)
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

	func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
		DispatchQueue.main.async { // need to wait for the UI to show up first, if the app is being launched and not foregrounded
			CloudManager.acceptShare(cloudKitShareMetadata)
		}
	}
}
