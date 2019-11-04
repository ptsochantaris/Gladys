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
        guard let activity = connectionOptions.userActivities.first ?? session.stateRestorationActivity else { return }
        setupDetail(scene: scene, activity: activity)
    }
        
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        setupDetail(scene: scene, activity: userActivity)
    }
    
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        guard let scene = scene as? UIWindowScene else { return nil }
        let n = scene.windows.first?.rootViewController as? UINavigationController
        return n?.viewControllers.first?.userActivity
    }

    private func setupDetail(scene: UIScene, activity: NSUserActivity) {
        guard //detail view
            let scene = scene as? UIWindowScene,
            activity.activityType == kGladysDetailViewingActivity,
            let userInfo = activity.userInfo,
            let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String,
            let item = Model.item(uuid: uuidString)
            else { return }

        showDetail(for: item, in: scene, count: 0)
    }
    
    private func showDetail(for item: ArchivedDropItem, in scene: UIWindowScene, count: Int) {
        if ViewController.shared == nil {
            if count == 0 {
                let v = UIViewController()
                v.view.backgroundColor = UIColor(named: "colorPaper")
                scene.windows.first?.rootViewController = v

            } else if count == 4 {
                UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil, errorHandler: nil)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showDetail(for: item, in: scene, count: count + 1)
            }
        } else {
            let d = scene.session.configuration.storyboard?.instantiateViewController(identifier: "Detail") as! DetailController
            d.item = item
            let n = UINavigationController(rootViewController: d)
            scene.windows.first?.rootViewController = n
        }
    }
}
