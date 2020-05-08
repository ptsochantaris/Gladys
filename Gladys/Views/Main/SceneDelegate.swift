//
//  SceneDelegate.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CloudKit

extension UIWindow {
    var alertPresenter: UIViewController? {
        var vc = self.rootViewController
        while let p = vc?.presentedViewController {
            if p is UIAlertController {
                break
            }
            vc = p
        }
        return vc
    }
}

extension UIScene {
    var firstController: UIViewController? {
        let n = (self as? UIWindowScene)?.windows.first?.rootViewController as? UINavigationController
        return n?.viewControllers.first
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        Singleton.shared.handleActivity(connectionOptions.userActivities.first ?? session.stateRestorationActivity, in: scene, useCentral: false)
        Singleton.shared.updateWindowCount()
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        Singleton.shared.updateWindowCount()
    }
    
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {

        if shortcutItem.type.hasSuffix(".Search") {
            Singleton.shared.showMaster(andHandle: NSUserActivity(activityType: kGladysStartSearchShortcutActivity), in: windowScene)

        } else if shortcutItem.type.hasSuffix(".Paste") {
            Singleton.shared.showMaster(andHandle: NSUserActivity(activityType: kGladysStartPasteShortcutActivity), in: windowScene)

        }
        completionHandler(true)
    }
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        Singleton.shared.handleActivity(userActivity, in: scene, useCentral: true)
    }
        
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let scene = scene as? UIWindowScene else { return }
        for c in URLContexts {
            self.openUrl(c.url, options: c.options, in: scene)
        }
    }
    
    private func openUrl(_ url: URL, options: UIScene.OpenURLOptions, in scene: UIWindowScene) {
        Singleton.shared.openUrl(url, options: options, in: scene)
    }
    
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        return scene.firstController?.userActivity
    }
            
    func sceneWillEnterForeground(_ scene: UIScene) {
        if UIApplication.shared.applicationState == .background {
            // just launching, or user was in another app
            if PersistedOptions.mirrorFilesToDocuments {
                Model.scanForMirrorChanges {}
            }
            CloudManager.opportunisticSyncIfNeeded()
        }
        Singleton.shared.updateWindowCount()
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        Singleton.shared.updateWindowCount()
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        Singleton.shared.updateWindowCount()
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        Singleton.shared.updateWindowCount()
    }
        
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        DispatchQueue.main.async { // need to wait for the UI to show up first, if the app is being launched and not foregrounded
            CloudManager.acceptShare(cloudKitShareMetadata)
        }
    }
}
