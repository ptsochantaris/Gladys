import BackgroundTasks
import CloudKit
import GladysCommon
import UIKit

extension CloudManager {
    enum SyncPermissionContext: Int {
        case always, wifiOnly, manualOnly
    }

    @EnumUserDefault(key: "syncContextSetting", defaultValue: .always)
    static var syncContextSetting: SyncPermissionContext

    static func received(notificationInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await Model.updateBadge()

        guard syncSwitchedOn, let notification = CKNotification(fromRemoteNotificationDictionary: notificationInfo) as? CKDatabaseNotification else {
            return .noData
        }

        let scope = notification.databaseScope
        log("Received \(scope.logName) DB change push")
        switch scope {
        case .private, .shared:
            if await UIApplication.shared.applicationState == .background {
                await Model.reloadDataIfNeeded()
            } else if !(await Model.doneIngesting) {
                log("We'll be syncing in a moment anyway, ignoring the push for now")
                return .newData
            }
            do {
                try await sync(scope: scope)
                return .newData
            } catch {
                log("Sync from push failed: \(error.localizedDescription)")
                return .failed
            }

        case .public:
            fallthrough

        @unknown default:
            return .noData
        }
    }

    static func syncAfterSaveIfNeeded() async throws {
        if !syncSwitchedOn {
            log("Sync switched off, no need to sync after save")
            return
        }

        switch syncContextSetting {
        case .always:
            log("Sync after a local save")
        case .wifiOnly:
            let go = await reachability.isReachableViaWiFi
            if go {
                log("Will sync after save, since WiFi is available")
            } else {
                log("Won't sync after save, because no WiFi")
                return
            }
        case .manualOnly:
            log("Won't sync after save, as manual sync is selected")
            return
        }

        try await sync()
    }

    static func opportunisticSyncIfNeeded(isStartup: Bool = false, force: Bool = false) async throws {
        let brs = await UIApplication.shared.backgroundRefreshStatus
        if syncSwitchedOn, !syncing, isStartup || force || brs != .available || lastSyncCompletion.timeIntervalSinceNow < -60 {
            // If there is no background fetch enabled, or it is, but we were in the background and we haven't heard from the server in a while
            try await sync()
        }
    }
}
