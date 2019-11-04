//
//  SceneDelegate.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit

extension UIScene {
    var isDetail: Bool {
        let n = (self as? UIWindowScene)?.windows.first?.rootViewController as? UINavigationController
        return n?.topViewController is DetailController
    }
    var firstGladysController: GladysViewController? {
        let n = (self as? UIWindowScene)?.windows.first?.rootViewController as? UINavigationController
        return n?.viewControllers.first as? GladysViewController
    }
}

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
        return scene.firstGladysController?.userActivity
    }
        
    func sceneWillEnterForeground(_ scene: UIScene) {
        if !scene.isDetail { // master scene
            if PersistedOptions.mirrorFilesToDocuments {
                Model.scanForMirrorChanges {}
            }
        }
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
            let n = scene.session.configuration.storyboard?.instantiateViewController(identifier: "DetailController") as! UINavigationController
            let d = n.viewControllers.first as! DetailController
            d.item = item
            scene.windows.first?.rootViewController = n
        }
    }
}
