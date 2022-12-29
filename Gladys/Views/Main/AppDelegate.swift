import CloudKit
import CoreSpotlight
import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
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
        Task { @CloudActor in
            let result = await CloudManager.received(notificationInfo: userInfo)
            completionHandler(result)
        }
    }
}
