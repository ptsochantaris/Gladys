import BackgroundTasks
import GladysCommon
import GladysUI
import Maintini
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @CloudActor in
            CloudManager.registerBackgroundHandling()
        }
        Maintini.setup()
        Singleton.shared.setup()
        application.registerForRemoteNotifications()
        Task {
            if let pushUserInfo = launchOptions?[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any] {
                _ = await CloudManager.received(notificationInfo: pushUserInfo)
            } else {
                do {
                    try await CloudManager.opportunisticSyncIfNeeded(force: true)
                } catch {
                    log("Error in startup sync: \(error.localizedDescription)")
                }
            }
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundRefreshTasks.bgRefreshTaskIdentifier, using: nil) { task in
            Task {
                do {
                    task.expirationHandler = {
                        log("Warning: Background refresh task was expired by the system")
                    }
                    log("Running scheduled background task")
                    try await CloudManager.syncAfterSaveIfNeeded()
                    for session in application.openSessions {
                        application.requestSceneSessionRefresh(session)
                    }
                    task.setTaskCompleted(success: true)
                } catch {
                    log("Failure while syncing based on background refresh request: \(error.localizedDescription)")
                    task.setTaskCompleted(success: false)
                }
            }
        }

        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
            await CloudManager.apnsUpdate(deviceToken)
        }
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError _: Error) {
        Task {
            await CloudManager.apnsUpdate(nil)
        }
    }

    func application(_: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        Maintini.startMaintaining()
        defer {
            Maintini.endMaintaining()
        }
        return await CloudManager.received(notificationInfo: userInfo)
    }
}
