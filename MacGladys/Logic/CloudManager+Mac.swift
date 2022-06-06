//
//  CloudManager.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import CloudKit
import Cocoa

extension CloudManager {
    static func received(notificationInfo: [AnyHashable: Any]) {
        if !syncSwitchedOn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Model.updateBadge()
            }
            return
        }

        guard let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo) as? CKDatabaseNotification else { return }
        let scope = notification.databaseScope
        log("Received \(scope.logName) DB change push")
        switch scope {
        case .private, .shared:
            if !Model.doneIngesting {
                log("We'll be syncing in a moment anyway, ignoring the push")
                return
            }
            Task {
                do {
                    try await sync(scope: scope)
                } catch {
                    log("Notification-triggered sync error: \(error.finalDescription)")
                }
            }
        case .public:
            break
        @unknown default:
            break
        }
    }

    static func opportunisticSyncIfNeeded() {
        if syncSwitchedOn, !syncing, lastSyncCompletion.timeIntervalSinceNow < -60 {
            Task {
                do {
                    try await sync()
                } catch {
                    log("Error in waking sync: \(error.finalDescription)")
                }
            }
        }
    }
}
