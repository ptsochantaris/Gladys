//
//  CloudManager.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa
import CloudKit

extension CloudManager {

	static func received(notificationInfo: [AnyHashable : Any]) {
		if !syncSwitchedOn {
			DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
				NSApplication.shared.dockTile.badgeLabel = nil
			}
			return
		}

		let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo)
		if notification.subscriptionID == privateDatabaseSubscriptionId || notification.subscriptionID == sharedDatabaseSubscriptionId {
			log("Received DB change push")
			sync { error in
				if let error = error {
					log("Notification-triggered sync error: \(error.finalDescription)")
				}
			}
		}
	}

	static func _sync(force: Bool, overridingWiFiPreference: Bool, completion: @escaping (Error?)->Void) {
		if !syncSwitchedOn { completion(nil); return }

		if syncing && !force {
			syncDirty = true
			completion(nil)
			return
		}

		syncing = true
		syncDirty = false

		func done(_ error: Error?) {
			syncing = false
			if let e = error {
				log("Sync failure: \(e.finalDescription)")
			}
			completion(error)
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
					_sync(force: true, overridingWiFiPreference: overridingWiFiPreference, completion: completion)
				} else {
					lastSyncCompletion = Date()
					done(nil)
				}
			}
		}
	}
}
