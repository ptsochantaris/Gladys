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

    static var onlySyncOverWiFi: Bool {
        get {
            return PersistedOptions.defaults.bool(forKey: "onlySyncOverWiFi")
        }

        set {
            PersistedOptions.defaults.set(newValue, forKey: "onlySyncOverWiFi")
        }
    }

	static func received(notificationInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		UIApplication.shared.applicationIconBadgeNumber = 0
		if !syncSwitchedOn { return }

		guard let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo) as? CKDatabaseNotification else { return }
		let scope = notification.databaseScope
		log("Received \(scope.logName) DB change push")
		switch scope {
		case .private, .shared:
			if UIApplication.shared.applicationState == .background {
				Model.reloadDataIfNeeded()
			} else if !Model.doneIngesting {
				log("We'll be syncing in a moment anyway, ignoring the push for now")
				completionHandler(.newData)
				return
			}
			sync(scope: scope) { error in
				if let error = error {
                    log("Sync from push failed: \(error.localizedDescription)")
					completionHandler(.failed)
				} else {
					completionHandler(.newData)
				}
			}
		case .public:
			break
		@unknown default:
			break
		}
	}

    static func opportunisticSyncIfNeeded(isStartup: Bool = false, force: Bool = false) {
        if isStartup && syncSwitchedOn {
            UIApplication.shared.registerForRemoteNotifications()
        }
		if syncSwitchedOn && !syncing && (isStartup || force || UIApplication.shared.backgroundRefreshStatus != .available || lastSyncCompletion.timeIntervalSinceNow < -60) {
			// If there is no background fetch enabled, or it is, but we were in the background and we haven't heard from the server in a while
			sync { error in
				if let error = error {
					log("Error in foregrounding sync: \(error.finalDescription)")
				}
			}
		}
	}
}
