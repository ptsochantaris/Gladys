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

    enum SyncPermissionContext: Int {
        case always, wifiOnly, manualOnly
    }
    
    @EnumUserDefault(key: "syncContextSetting", defaultValue: .always)
    static var syncContextSetting: SyncPermissionContext

	static func received(notificationInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: ((UIBackgroundFetchResult) -> Void)?) {
        Model.updateBadge()
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
				completionHandler?(.newData)
				return
			}
            Task {
                do {
                    try await sync(scope: scope)
                    completionHandler?(.newData)
                } catch {
                    log("Sync from push failed: \(error.localizedDescription)")
                    completionHandler?(.failed)
                }
            }
		case .public:
			break
		@unknown default:
			break
		}
	}
    
    static func syncAfterSaveIfNeeded() {
        if !syncSwitchedOn {
            log("Sync switched off, no need to sync after save")
            return
        }
        
        let go: Bool
        switch CloudManager.syncContextSetting {
        case .always:
            go = true
            log("Sync after a local save")
        case .wifiOnly:
            go = reachability.status == .reachableViaWiFi
            if go {
                log("Will sync after save, since WiFi is available")
            } else {
                log("Won't sync after save, because no WiFi")
            }
        case .manualOnly:
            go = false
            log("Won't sync after save, as manual sync is selected")
        }
        
        if !go { return }
        
        Task {
            do {
                try await CloudManager.sync()
            } catch {
                log("Error in sync after save: \(error.finalDescription)")
            }
        }
    }

    static func opportunisticSyncIfNeeded(isStartup: Bool = false, force: Bool = false) {
		if syncSwitchedOn && !syncing && (isStartup || force || UIApplication.shared.backgroundRefreshStatus != .available || lastSyncCompletion.timeIntervalSinceNow < -60) {
			// If there is no background fetch enabled, or it is, but we were in the background and we haven't heard from the server in a while
            Task {
                do {
                    try await sync()
                } catch {
                    log("Error in foregrounding sync: \(error.finalDescription)")
                }
            }
		}
	}
}
