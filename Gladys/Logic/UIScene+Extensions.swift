import GladysCommon
import UIKit

extension UISceneSession {
    var isAccessoryWindow: Bool {
        !isMainWindow
    }

    var isMainWindow: Bool {
        if stateRestorationActivity?.activityType == kGladysMainListActivity {
            return true
        }
        if let mainActivity = ((scene as? UIWindowScene)?.windows.first?.rootViewController as? UINavigationController)?.viewControllers.first?.userActivity?.activityType {
            return mainActivity == kGladysMainListActivity
        }
        return false
    }
}

extension UIWindowScene {
    var isAccessoryWindow: Bool {
        session.isAccessoryWindow
    }
}
