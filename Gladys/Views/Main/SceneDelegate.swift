//
//  SceneDelegate.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CoreSpotlight

extension UISceneSession {
    var isMaster: Bool {
        return stateRestorationActivity == nil
    }
}

extension UIScene {
    var isMaster: Bool {
        return session.isMaster
    }
    var firstController: UIViewController? {
        let n = (self as? UIWindowScene)?.windows.first?.rootViewController as? UINavigationController
        return n?.viewControllers.first
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let activity = connectionOptions.userActivities.first { // new scene
            handleActivity(activity, in: scene)
            
        } else if let activity = session.stateRestorationActivity { // restoring scene
            handleActivity(activity, in: scene)
        }
    }
    
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        ViewController.executeOrQueue {
            if shortcutItem.type.hasSuffix(".Search") {
                ViewController.shared.startSearch(initialText: nil)
            } else if shortcutItem.type.hasSuffix(".Paste") {
                ViewController.shared.forcePaste()
            }
            completionHandler(true)
        }
    }
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleActivity(userActivity, in: scene) // handoff
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for c in URLContexts {
            openUrl(c.url, options: c.options)
        }
    }
    
    private func openUrl(_ url: URL, options: UIScene.OpenURLOptions) {
        
        if let c = url.host, c == "inspect-item", let itemId = url.pathComponents.last {
            ViewController.executeOrQueue {
                let request = HighlightRequest(uuid: itemId, open: true)
                NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
            }
            
        } else if let c = url.host, c == "in-app-purchase", let p = url.pathComponents.last, let t = Int(p) {
            ViewController.executeOrQueue {
                IAPManager.shared.displayRequest(newTotal: t)
            }
            
        } else if let c = url.host, c == "paste-clipboard" { // this is legacy
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let titleParameter = components?.queryItems?.first { $0.name == "title" || $0.name == "label" }
            let noteParameter = components?.queryItems?.first { $0.name == "note" }
            let labelsList = components?.queryItems?.first { $0.name == "labels" }
            ViewController.executeOrQueue {
                CallbackSupport.handlePasteRequest(title: titleParameter?.value, note: noteParameter?.value, labels: labelsList?.value, skipVisibleErrors: false)
            }
            
        } else if url.host == nil { // just opening
            if url.isFileURL, url.pathExtension.lowercased() == "gladysarchive" {
                let a = UIAlertController(title: "Import Archive?", message: "Import items from \"\(url.deletingPathExtension().lastPathComponent)\"?", preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "Import", style: .destructive) { _ in
                    var securityScoped = false
                    if options.openInPlace {
                        securityScoped = url.startAccessingSecurityScopedResource()
                    }
                    do {
                        try Model.importArchive(from: url, removingOriginal: !options.openInPlace)
                    } catch {
                        genericAlert(title: "Could not import data", message: error.finalDescription)
                    }
                    if securityScoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                })
                a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                ViewController.executeOrQueue {
                    SceneDelegate.top.present(a, animated: true)
                }
            }
            
        } else if !PersistedOptions.blockGladysUrlRequests {
            ViewController.executeOrQueue {
                CallbackSupport.handlePossibleCallbackURL(url: url)
            }
        }
    }
    
    private func handleActivity(_ userActivity: NSUserActivity, in scene: UIScene) {
        guard let scene = scene as? UIWindowScene else { return }
        waitForBoot(in: scene) {
            self.handleActivityAfterBoot(userActivity: userActivity, in: scene)
        }
    }
    
    private func handleActivityAfterBoot(userActivity: NSUserActivity, in scene: UIWindowScene) {
        
        scene.session.stateRestorationActivity = userActivity
                                
        switch userActivity.activityType {
        case kGladysQuicklookActivity:
            if //detail view
                let userInfo = userActivity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String,
                let item = Model.item(uuid: uuidString) {
                    
                let child: ArchivedDropItemType?
                if let childUuid = userInfo[kGladysDetailViewingActivityItemTypeUuid] as? String {
                    child = Model.typeItem(uuid: childUuid)
                } else {
                    child = item.previewableTypeItem
                }
                
                if let child = child {
                    guard let q = child.quickLook(in: scene) else { return }
                    let n = PreviewHostingViewController(rootViewController: q)
                    scene.windows.first?.rootViewController = n

                } else {
                    UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
                }
            }

        case kGladysDetailViewingActivity:
            if //detail view
                let userInfo = userActivity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String,
                let item = Model.item(uuid: uuidString) {

                let n = scene.session.configuration.storyboard?.instantiateViewController(identifier: "DetailController") as! UINavigationController
                let d = n.viewControllers.first as! DetailController
                d.item = item
                scene.windows.first?.rootViewController = n
            } else {
                UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
            }

        case CSSearchableItemActionType:
            if let itemIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                let request = HighlightRequest(uuid: itemIdentifier)
                NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
            }

        case CSQueryContinuationActionType:
            if let searchQuery = userActivity.userInfo?[CSSearchQueryString] as? String {
                ViewController.shared.startSearch(initialText: searchQuery)
            }
            
        default: break
        }
    }
    
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        return scene.firstController?.userActivity
    }
        
    func sceneWillEnterForeground(_ scene: UIScene) {
        if scene.isMaster { // master scene
            if PersistedOptions.mirrorFilesToDocuments {
                Model.scanForMirrorChanges {}
            }
        }
        CloudManager.opportunisticSyncIfNeeded(isStartup: false)
    }
        
    private func waitForBoot(count: Int = 0, in scene: UIWindowScene, completion: @escaping ()->Void) {
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
    
    static var top: UIViewController {
        let searchController = ViewController.shared.navigationItem.searchController
        let searching = searchController?.isActive ?? false
        var finalVC: UIViewController = (searching ? searchController : nil) ?? ViewController.shared
        while let newVC = finalVC.presentedViewController {
            if newVC is UIAlertController { break }
            finalVC = newVC
        }
        return finalVC
    }
}
