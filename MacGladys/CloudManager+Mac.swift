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

		guard let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo) as? CKDatabaseNotification else { return }
		switch notification.databaseScope {
		case .private:
			log("Received private DB change push")
			if !Model.doneIngesting {
				log("We'll be syncing in a moment anyway, ignoring the push")
				return
			}
			sync(scope: .private) { error in
				if let error = error {
					log("Notification-triggered sync error: \(error.finalDescription)")
				}
			}
		case .public:
			break
		case .shared:
			log("Received shared DB change push")
			if !Model.doneIngesting {
				log("We'll be syncing in a moment anyway, ignoring the push")
				return
			}
			sync(scope: .shared) { error in
				if let error = error {
					log("Notification-triggered sync error: \(error.finalDescription)")
				}
			}
		}
	}
}
