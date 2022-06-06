//
//  UIScene+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 11/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

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

    var isMainWindow: Bool {
        session.isMainWindow
    }
}
