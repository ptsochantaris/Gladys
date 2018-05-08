//
//  CloudManager+MainApp.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 27/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CloudKit
import UIKit

extension CloudManager {

	static func received(notificationInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		UIApplication.shared.applicationIconBadgeNumber = 0
		if !syncSwitchedOn { return }

		let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo)
		if notification.subscriptionID == "private-changes" {
			log("Received zone change push")
			if UIApplication.shared.applicationState == .background {
				Model.reloadDataIfNeeded()
			}
			sync { error in
				if error != nil {
					completionHandler(.failed)
				} else {
					completionHandler(.newData)
				}
			}
		}
	}

	static func opportunisticSyncIfNeeded(isStartup: Bool) {
		if syncSwitchedOn && !syncing && (isStartup || UIApplication.shared.backgroundRefreshStatus != .available || lastSyncCompletion.timeIntervalSinceNow < -60) {
			// If there is no background fetch enabled, or it is, but we were in the background and we haven't heard from the server in a while
			sync { error in
				if let error = error {
					log("Error in foregrounding sync: \(error.finalDescription)")
				}
			}
		}
	}

	static func _sync(force: Bool, overridingWiFiPreference: Bool, existingBgTask: UIBackgroundTaskIdentifier? = nil, completion: @escaping (Error?)->Void) {
		if !syncSwitchedOn { completion(nil); return }

		if !force && !overridingWiFiPreference && onlySyncOverWiFi && reachability.status != .ReachableViaWiFi {
			log("Skipping sync because no WiFi is present and user has selected WiFi sync only")
			completion(nil)
			return
		}

		if syncing && !force {
			syncDirty = true
			completion(nil)
			return
		}

		let bgTask: UIBackgroundTaskIdentifier
		if let e = existingBgTask {
			bgTask = e
		} else {
			log("Starting cloud sync background task")
			bgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.gladys.syncTask", expirationHandler: nil)
		}

		syncing = true
		syncDirty = false

		func done(_ error: Error?) {
			syncing = false
			if let e = error {
				log("Sync failure: \(e.finalDescription)")
			}
			completion(error)
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				log("Ending cloud sync background task")
				UIApplication.shared.endBackgroundTask(bgTask)
			}
		}

		sendUpdatesUp { error in
			if let error = error {
				done(error)
				return
			}

			fetchDatabaseChanges { error in
				if let error = error {
					done(error)
				} else if syncDirty {
					_sync(force: true, overridingWiFiPreference:overridingWiFiPreference, existingBgTask: bgTask, completion: completion)
				} else {
					lastSyncCompletion = Date()
					done(nil)
				}
			}
		}
	}
}
