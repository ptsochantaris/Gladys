import CloudKit
import GladysCommon
import GladysUI
import Maintini
import UIKit

extension CloudManager {
    enum SyncPermissionContext: Int {
        case always, wifiOnly, manualOnly
    }

    @EnumUserDefault(key: "syncContextSetting", defaultValue: .always)
    static var syncContextSetting: SyncPermissionContext

    @MainActor
    static func received(notificationInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        Model.updateBadge()

        if let notification = CKDatabaseNotification(fromRemoteNotificationDictionary: notificationInfo) {
            return await _received(notification: notification)
        } else {
            return .noData
        }
    }

    static private func _received(notification: CKDatabaseNotification) async -> UIBackgroundFetchResult {

        guard syncSwitchedOn else {
            return .noData
        }

        let scope = notification.databaseScope
        log("Received \(scope.logName) DB change push")
        switch scope {
        case .private, .shared:
            if await DropStore.processingItems {
                log("We'll be syncing in a moment anyway, ignoring the push for now")
                return .newData
            }
            if await UIApplication.shared.applicationState != .active {
                try! await Model.reloadDataIfNeeded()
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

    static func registerBackgroundHandling() {
        shouldSyncAttemptProceed = { force in
            if force {
                return true
            }
            if syncContextSetting == .wifiOnly, await !Reachability.shared.isReachableViaLowCost {
                log("Skipping auto sync because no WiFi is present and user has selected WiFi sync only")
                return false
            }
            if syncContextSetting == .manualOnly {
                log("Skipping auto sync because user selected manual sync only")
                return false
            }
            return true
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
            if await Reachability.shared.isReachableViaLowCost {
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
}
