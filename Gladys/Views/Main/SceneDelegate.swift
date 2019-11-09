//
//  SceneDelegate.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 03/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit
import CoreSpotlight

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

var componentDropActiveFromDetailView: DetailController?

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    override init() {
        super.init()
        
        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(ingestStart(_:)), name: .IngestStart, object: nil)
        n.addObserver(self, selector: #selector(ingestComplete(_:)), name: .IngestComplete, object: nil)
        n.addObserver(self, selector: #selector(externalDataUpdate), name: .ExternalDataUpdated, object: nil)
    }
    
    @objc private func externalDataUpdate() {
        Model.forceUpdateFilter(signalUpdate: false) // will force below
        Model.detectExternalChanges()
    }
    
    private var ingestRunning = false
    @objc private func ingestStart(_ notification: Notification) {
        if !ingestRunning {
            ingestRunning = true
            BackgroundTask.registerForBackground()
        }
    }
    
    @objc private func ingestComplete(_ notification: Notification) {
        guard let item = notification.object as? ArchivedDropItem else { return }
        if Model.doneIngesting {
            Model.save()
            if ingestRunning {
                BackgroundTask.unregisterForBackground()
                ingestRunning = false
            }
        } else {
            Model.commitItem(item: item)
        }
    }
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let activity = connectionOptions.userActivities.first { // new scene
            handleActivity(activity, in: scene)
            
        } else {
            handleActivity(session.stateRestorationActivity, in: scene)
        }
    }
    
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        waitForBoot(in: windowScene) {
            if shortcutItem.type.hasSuffix(".Search") {
                NotificationCenter.default.post(name: .StartSearchRequest, object: nil)
            } else if shortcutItem.type.hasSuffix(".Paste") {
                NotificationCenter.default.post(name: .ForcePasteRequest, object: nil)
            }
            completionHandler(true)
        }
    }
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleActivity(userActivity, in: scene) // handoff
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let scene = scene as? UIWindowScene else { return }
        waitForBoot(in: scene) {
            for c in URLContexts {
                self.openUrl(c.url, options: c.options, in: scene)
            }
        }
    }
    
    private func openUrl(_ url: URL, options: UIScene.OpenURLOptions, in scene: UIWindowScene) {
        
        if let c = url.host, c == "inspect-item", let itemId = url.pathComponents.last {
            let request = HighlightRequest(uuid: itemId, open: true)
            NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
            
        } else if let c = url.host, c == "in-app-purchase", let p = url.pathComponents.last, let t = Int(p) {
            IAPManager.shared.displayRequest(newTotal: t)
                        
        } else if url.host == nil { // just opening
            if url.isFileURL, url.pathExtension.lowercased() == "gladysarchive", let presenter = scene.windows.first?.alertPresenter {
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
                presenter.present(a, animated: true)
            }
            
        } else if !PersistedOptions.blockGladysUrlRequests {
            CallbackSupport.handlePossibleCallbackURL(url: url)
        }
    }
    
    private func handleActivity(_ userActivity: NSUserActivity?, in scene: UIScene) {
        guard let scene = scene as? UIWindowScene else { return }
        waitForBoot(in: scene) {
            self.handleActivityAfterBoot(userActivity: userActivity, in: scene)
        }
    }
        
    private func handleActivityAfterBoot(userActivity: NSUserActivity?, in scene: UIWindowScene) {
        
        scene.session.stateRestorationActivity = userActivity
                                
        switch userActivity?.activityType {
        case kGladysQuicklookActivity:
            if
                let userActivity = userActivity,
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
                    return

                }
            }

        case kGladysDetailViewingActivity:
            if
                let userActivity = userActivity,
                let userInfo = userActivity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String,
                let item = Model.item(uuid: uuidString) {

                let n = scene.session.configuration.storyboard?.instantiateViewController(identifier: "DetailController") as! UINavigationController
                let d = n.viewControllers.first as! DetailController
                d.item = item
                scene.windows.first?.rootViewController = n
                return
            }

        case CSSearchableItemActionType:
            if let userActivity = userActivity, let itemIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                let request = HighlightRequest(uuid: itemIdentifier)
                NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
                return
            }

        case CSQueryContinuationActionType:
            if let userActivity = userActivity, let searchQuery = userActivity.userInfo?[CSSearchQueryString] as? String {
                NotificationCenter.default.post(name: .StartSearchRequest, object: searchQuery)
                return
            }
            
        default:
            scene.windows.first?.rootViewController = scene.session.configuration.storyboard?.instantiateViewController(identifier: "Central")
            return
        }
        
        UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
    }
    
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        return scene.firstController?.userActivity
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        booted = true
    }
        
    func sceneWillEnterForeground(_ scene: UIScene) {
        if PersistedOptions.mirrorFilesToDocuments {
            Model.scanForMirrorChanges {}
        }
        CloudManager.opportunisticSyncIfNeeded(isStartup: false)
    }
    
    private var booted = false
    
    private func waitForBoot(count: Int = 0, in scene: UIWindowScene, completion: @escaping ()->Void) {
        if booted {
            completion()
            return
        }

        if count == 0 {
            let v = UIViewController()
            v.view.backgroundColor = UIColor(named: "colorPaper")
            scene.windows.first?.rootViewController = v
            
        } else if count == 10 {
            UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.waitForBoot(count: count + 1, in: scene, completion: completion)
        }
    }
}
