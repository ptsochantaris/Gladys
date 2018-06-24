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

		guard let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo) as? CKDatabaseNotification else { return }
		switch notification.databaseScope {
		case .private:
			log("Received private DB change push")
			if UIApplication.shared.applicationState == .background {
				Model.reloadDataIfNeeded()
			} else if !Model.doneIngesting {
				log("We'll be syncing in a moment anyway, ignoring the push for now")
				completionHandler(.newData)
				return
			}
			sync(scope: .private) { error in
				if error != nil {
					completionHandler(.failed)
				} else {
					completionHandler(.newData)
				}
			}
		case .public:
			break
		case .shared:
			log("Received shared DB change push")
			if UIApplication.shared.applicationState == .background {
				Model.reloadDataIfNeeded()
			} else if !Model.doneIngesting {
				log("We'll be syncing in a moment anyway, ignoring the push for now")
				completionHandler(.newData)
				return
			}
			sync(scope: .shared) { error in
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
}
