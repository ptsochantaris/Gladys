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
    
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
		UIApplication.shared.applicationIconBadgeNumber = 0
		Model.reloadDataIfNeeded()
		PullState.checkMigrations()
		if CloudManager.syncSwitchedOn {
			UIApplication.shared.registerForRemoteNotifications()
		}
		log("Initial reachability status: \(reachability.status.name)")
		CallbackSupport.setupCallbackSupport()
		IAPManager.shared.start()
        
        for s in application.openSessions where !s.isMaster { // kill all detail views
            application.requestSceneSessionDestruction(s, options: nil, errorHandler: nil)
        }
        
        let masterSessions = application.openSessions.filter { $0.isMaster }
        masterSessions.dropFirst().forEach { // kill all masters except one
            application.requestSceneSessionDestruction($0, options: nil, errorHandler: nil)
        }
        
		return true
	}
    
	func applicationWillTerminate(_ application: UIApplication) {
		IAPManager.shared.stop()
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
