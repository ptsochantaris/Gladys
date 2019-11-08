//
//  SceneDelegate.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CoreSpotlight

extension UIScene {
    var isDetail: Bool {
        let n = (self as? UIWindowScene)?.windows.first?.rootViewController as? UINavigationController
        return n?.topViewController is DetailController
    }
    var firstController: UIViewController? {
        let n = (self as? UIWindowScene)?.windows.first?.rootViewController as? UINavigationController
        return n?.viewControllers.first
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let activity = connectionOptions.userActivities.first ?? session.stateRestorationActivity
        setupScene(scene: scene, activity: activity)
    }
        
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        setupScene(scene: scene, activity: userActivity)
    }
    
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        return scene.firstController?.userActivity
    }
        
    func sceneWillEnterForeground(_ scene: UIScene) {
        if !scene.isDetail { // master scene
            if PersistedOptions.mirrorFilesToDocuments {
                Model.scanForMirrorChanges {}
            }
        }
    }
        
    private func setupScene(scene: UIScene, activity: NSUserActivity?) {
        guard let scene = scene as? UIWindowScene else { return }

        let app = UIApplication.shared
        
        guard let activity = activity else {
            // don't start two mains
            for otherMain in app.openSessions.filter({ $0.stateRestorationActivity == nil && $0 !== scene.session }) {
                app.requestSceneSessionDestruction(otherMain, options: nil, errorHandler: nil)
            }
            return // no activity, we're done
        }
        
        if scene.session.stateRestorationActivity == nil {
            scene.session.stateRestorationActivity = activity
        }
        
        switch activity.activityType {
        case kGladysQuicklookActivity:
            if //detail view
                let userInfo = activity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String,
                let item = Model.item(uuid: uuidString) {
                waitForBoot(count: 0, in: scene) {
                    
                    let child: ArchivedDropItemType?
                    if let childUuid = userInfo[kGladysDetailViewingActivityItemTypeUuid] as? String {
                        child = Model.typeItem(uuid: childUuid)
                    } else {
                        child = item.previewableTypeItem
                    }
                    
                    if let child = child {
                        self.showQuicklook(for: item, child: child, in: scene)
                    } else {
                        UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
                    }
                }
            }

        case kGladysDetailViewingActivity:
            if //detail view
                let userInfo = activity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String,
                let item = Model.item(uuid: uuidString) {
                waitForBoot(count: 0, in: scene) {
                    self.showDetail(for: item, in: scene)
                }
            }

        case CSSearchableItemActionType:
            if let itemIdentifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                ViewController.shared.highlightItem(with: itemIdentifier)
            }

        case CSQueryContinuationActionType:
            if let searchQuery = activity.userInfo?[CSSearchQueryString] as? String {
                ViewController.shared.startSearch(initialText: searchQuery)
            }
            
        default: break
        }
        
        //if sessionForMain == nil { // need main app instance before we proceed
            //app.requestSceneSessionActivation(nil, userActivity: nil, options: nil, errorHandler: nil)
        //}
    }
    
    private func waitForBoot(count: Int, in scene: UIWindowScene, completion: @escaping ()->Void) {
        if ViewController.shared == nil {
            if count == 0 {
                let v = UIViewController()
                v.view.backgroundColor = UIColor(named: "colorPaper")
                scene.windows.first?.rootViewController = v
                
            } else if count == 10 {
                UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
                return
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.waitForBoot(count: count + 1, in: scene, completion: completion)
            }
        } else {
            completion()
        }
    }
    
    private func showDetail(for item: ArchivedDropItem, in scene: UIWindowScene) {
        let n = scene.session.configuration.storyboard?.instantiateViewController(identifier: "DetailController") as! UINavigationController
        let d = n.viewControllers.first as! DetailController
        d.item = item
        scene.windows.first?.rootViewController = n
    }
    
    private func showQuicklook(for item: ArchivedDropItem, child: ArchivedDropItemType, in scene: UIWindowScene) {
        guard let q = child.quickLook(in: scene) else { return }
        let n = PreviewHostingViewController(rootViewController: q)
        scene.windows.first?.rootViewController = n
    }
}
