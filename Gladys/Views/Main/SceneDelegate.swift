//
//  SceneDelegate.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import CloudKit
import UIKit

extension UIWindow {
    var alertPresenter: UIViewController? {
        var vc = rootViewController
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

    var mainController: ViewController? {
        if let n = (self as? UIWindowScene)?.windows.first?.rootViewController as? UINavigationController, let vc = n.viewControllers.first as? ViewController {
            return vc
        }
        return nil
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let forceMainWindow = !UIApplication.shared.supportsMultipleScenes
        Singleton.shared.handleActivity(connectionOptions.userActivities.first ?? session.stateRestorationActivity, in: scene, forceMainWindow: forceMainWindow)
        updateWindowCount()
    }

    func sceneDidDisconnect(_: UIScene) {
        updateWindowCount()
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type.hasSuffix(".Search") {
            Singleton.shared.boot(with: NSUserActivity(activityType: kGladysStartSearchShortcutActivity), in: windowScene)

        } else if shortcutItem.type.hasSuffix(".Paste") {
            Singleton.shared.boot(with: NSUserActivity(activityType: kGladysStartPasteShortcutActivity), in: windowScene)
        }
        completionHandler(true)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        Singleton.shared.handleActivity(userActivity, in: scene, forceMainWindow: true)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let scene = scene as? UIWindowScene else { return }
        for c in URLContexts {
            openUrl(c.url, options: c.options, in: scene)
        }
    }

    private func openUrl(_ url: URL, options: UIScene.OpenURLOptions, in scene: UIWindowScene) {
        Singleton.shared.openUrl(url, options: options, in: scene)
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        scene.firstController?.userActivity
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        BackgroundTask.appForegrounded()
        updateWindowCount()
        log("Scene foregrounded")
        if let vc = scene.mainController {
            vc.sceneForegrounded()
        }
    }

    func sceneWillResignActive(_: UIScene) {
        updateWindowCount()
    }

    func sceneDidEnterBackground(_: UIScene) {
        BackgroundTask.appBackgrounded()
        updateWindowCount()
        log("Scene backgrounded")
    }

    func sceneDidBecomeActive(_: UIScene) {
        updateWindowCount()
        Model.updateBadge()
    }

    private func updateWindowCount() {
        Singleton.shared.openCount = UIApplication.shared.connectedScenes.reduce(0) {
            if $1.activationState == .background {
                return $0
            }
            return $0 + 1
        }
        if let c = currentWindow {
            lastUsedWindow = c
        }
    }

    func windowScene(_: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        DispatchQueue.main.async { // need to wait for the UI to show up first, if the app is being launched and not foregrounded
            CloudManager.acceptShare(cloudKitShareMetadata)
        }
    }
}
