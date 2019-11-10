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
        Model.beginMonitoringChanges() // will reload data as well
		PullState.checkMigrations()
		if CloudManager.syncSwitchedOn {
			UIApplication.shared.registerForRemoteNotifications()
		}
		CallbackSupport.setupCallbackSupport()
		IAPManager.shared.start()
        Model.detectExternalChanges()
        CloudManager.opportunisticSyncIfNeeded(isStartup: true)

        log("Initial reachability status: \(reachability.status.name)")
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

	func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
		DispatchQueue.main.async { // need to wait for the UI to show up first, if the app is being launched and not foregrounded
			CloudManager.acceptShare(cloudKitShareMetadata)
		}
	}
}
