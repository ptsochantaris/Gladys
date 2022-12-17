import CloudKit
import CoreSpotlight
import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Singleton.shared.setup()

        if let pushUserInfo = launchOptions?[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any] {
            CloudManager.received(notificationInfo: pushUserInfo, fetchCompletionHandler: nil)
        } else {
            CloudManager.opportunisticSyncIfNeeded(isStartup: true)
        }

        UIApplication.shared.registerForRemoteNotifications()

        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        CloudManager.apnsUpdate(deviceToken)
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        CloudManager.apnsUpdate(nil)
    }

    func application(_: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        CloudManager.received(notificationInfo: userInfo, fetchCompletionHandler: completionHandler)
    }
}
