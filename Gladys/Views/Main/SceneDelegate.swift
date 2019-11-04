//
//  SceneDelegate.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        setupDetail(scene: scene, activities: connectionOptions.userActivities)
    }
        
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        setupDetail(scene: scene, activities: [userActivity])
    }
        
    private func setupDetail(scene: UIScene, activities: Set<NSUserActivity>) {
        
        for activity in activities {
            guard //detail view
                let scene = scene as? UIWindowScene,
                activity.activityType == kGladysDetailViewingActivity,
                let userInfo = activity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String,
                let item = Model.item(uuid: uuidString)
                else { continue }

            let d = scene.session.configuration.storyboard?.instantiateViewController(identifier: "Detail") as! DetailController
            d.item = item
            let n = UINavigationController(rootViewController: d)
            scene.windows.first?.rootViewController = n
        }
    }
}
