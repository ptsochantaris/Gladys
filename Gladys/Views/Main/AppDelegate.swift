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
    
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Singleton.shared.setup()
        
        if let pushUserInfo = launchOptions?[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any] {
            CloudManager.received(notificationInfo: pushUserInfo, fetchCompletionHandler: nil)
        } else {
            CloudManager.opportunisticSyncIfNeeded(isStartup: true)
        }
        
        UIApplication.shared.registerForRemoteNotifications()
        
		return true
	}
    
	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
		log("APNS ready: \(deviceToken.base64EncodedString())")
		CloudManager.apnsUpdate(deviceToken)
	}

	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
		log("Warning: APNS registration failed: \(error.finalDescription)")
		CloudManager.apnsUpdate(nil)
	}

	func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		CloudManager.received(notificationInfo: userInfo, fetchCompletionHandler: completionHandler)
	}
}
