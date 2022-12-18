import CloudKit
import Cocoa

extension CloudManager {
    static func received(notificationInfo: [AnyHashable: Any]) {
        if !syncSwitchedOn {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
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
    
    static func syncAfterSaveIfNeeded() {
        if !syncSwitchedOn {
            log("Sync switched off, no need to sync after save")
            return
        }

        Task {
            do {
                try await CloudManager.sync()
            } catch {
                log("Error in sync after save: \(error.finalDescription)")
            }
        }
    }

}
