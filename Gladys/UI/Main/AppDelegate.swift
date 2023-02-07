import CloudKit
import CoreSpotlight
import GladysCommon
import UIKit
import GladysUI

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @CloudActor in
            CloudManager.registerBackgroundHandling()
        }
        Singleton.shared.setup()
        UIApplication.shared.registerForRemoteNotifications()
        Task {
            if let pushUserInfo = launchOptions?[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any] {
                _ = await CloudManager.received(notificationInfo: pushUserInfo)
            } else {
                do {
                    try await CloudManager.opportunisticSyncIfNeeded(isStartup: true)
                } catch {
                    log("Error in startup sync: \(error.finalDescription)")
                }
            }
        }
        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @CloudActor in
            CloudManager.apnsUpdate(deviceToken)
        }
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError _: Error) {
        Task { @CloudActor in
            CloudManager.apnsUpdate(nil)
        }
    }

    func application(_: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        BackgroundTask.registerForBackground()
        Task { @CloudActor in
            let result = await CloudManager.received(notificationInfo: userInfo)
            await BackgroundTask.unregisterForBackground()
            completionHandler(result)
        }
    }
}
