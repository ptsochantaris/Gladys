import CloudKit
import GladysCommon
import GladysUI

extension CloudManager {
    static func received(notificationInfo: [AnyHashable: Any]) async {
        guard syncSwitchedOn else {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            await Model.updateBadge()
            return
        }

        guard let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo) as? CKDatabaseNotification else { return }
        let scope = notification.databaseScope
        log("Received \(scope.logName) DB change push")
        switch scope {
        case .private, .shared:
            guard await DropStore.doneIngesting else {
                log("We'll be syncing in a moment anyway, ignoring the push")
                return
            }
            do {
                try await sync(scope: scope)
            } catch {
                log("Notification-triggered sync error: \(error.finalDescription)")
            }
        case .public:
            break
        @unknown default:
            break
        }
    }

    static func syncAfterSaveIfNeeded() async throws {
        if !syncSwitchedOn {
            log("Sync switched off, no need to sync after save")
            return
        }

        try await sync()
    }
}
