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

extension UIScene {
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
        
        Model.reloadDataIfNeeded()
        Model.checkForUpgrade()

        if !PersistedOptions.pasteShortcutAutoDonated {
            Model.donatePasteIntent()
        }
        
        if PersistedOptions.mirrorFilesToDocuments {
            MirrorManager.startMirrorMonitoring()
        }

        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(ingestStart(_:)), name: .IngestStart, object: nil)
        n.addObserver(self, selector: #selector(ingestComplete(_:)), name: .IngestComplete, object: nil)
        n.addObserver(self, selector: #selector(modelDataUpdate), name: .ModelDataUpdated, object: nil)
    }
    
    @objc private func modelDataUpdate() {
        Model.detectExternalChanges()
        for session in UIApplication.shared.openSessions where session.scene?.activationState == .background {
            UIApplication.shared.requestSceneSessionRefresh(session)
        }
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
        handleActivity(connectionOptions.userActivities.first ?? session.stateRestorationActivity, in: scene, useCentral: false)
        checkWindowCount()
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        checkWindowCount()
    }
    
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {

        if shortcutItem.type.hasSuffix(".Search") {
            showMaster(andHandle: NSUserActivity(activityType: kGladysStartSearchShortcutActivity), in: windowScene)

        } else if shortcutItem.type.hasSuffix(".Paste") {
            showMaster(andHandle: NSUserActivity(activityType: kGladysStartPasteShortcutActivity), in: windowScene)

        }
        completionHandler(true)
    }
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleActivity(userActivity, in: scene, useCentral: true)
    }
    
    private func showMaster(andHandle activity: NSUserActivity?, in scene: UIScene?) {
        let masterSession = UIApplication.shared.openSessions.first { $0.isMainWindow }
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = scene
        UIApplication.shared.requestSceneSessionActivation(masterSession, userActivity: activity, options: options, errorHandler: nil)
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let scene = scene as? UIWindowScene else { return }
        for c in URLContexts {
            self.openUrl(c.url, options: c.options, in: scene)
        }
    }
    
    private func openUrl(_ url: URL, options: UIScene.OpenURLOptions, in scene: UIWindowScene) {
        
        if let c = url.host, c == "inspect-item", let itemId = url.pathComponents.last {
            let activity = NSUserActivity(activityType: CSSearchableItemActionType)
            activity.userInfo = [CSSearchableItemActivityIdentifier: itemId]
            showMaster(andHandle: activity, in: scene)
            
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
    
    private func handleActivity(_ userActivity: NSUserActivity?, in scene: UIScene, useCentral: Bool) {
        guard let scene = scene as? UIWindowScene else { return }
        
        scene.session.stateRestorationActivity = userActivity
        
        switch userActivity?.activityType {
        case kGladysMainListActivity:
            
            let labelList: Set<String>?
            if let list = userActivity?.userInfo?[kGladysMainViewLabelList] as? [String], !list.isEmpty {
                labelList = Set(list)
            } else {
                labelList = nil
            }
            showCentral(in: scene, restoringLabels: labelList)
            return

        case kGladysQuicklookActivity:
            if
                let userActivity = userActivity,
                let userInfo = userActivity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String {

                guard let item = Model.item(uuid: uuidString) else {
                    showCentral(in: scene) { _ in
                        genericAlert(title: "Not Found", message: "This item was not found")
                    }
                    return
                }
                
                let child: ArchivedDropItemType?
                if let childUuid = userInfo[kGladysDetailViewingActivityItemTypeUuid] as? String {
                    child = Model.typeItem(uuid: childUuid)
                } else {
                    child = item.previewableTypeItem
                }
                if useCentral {
                    showCentral(in: scene) { vc in
                        let request = HighlightRequest(uuid: uuidString, open: false, preview: true, focusOnChildUuid: child?.uuid.uuidString)
                        NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
                    }
                    return
                    
                } else if let child = child {
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
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String {

                guard let item = Model.item(uuid: uuidString) else {
                    showCentral(in: scene) { _ in
                        genericAlert(title: "Not Found", message: "This item was not found")
                    }
                    return
                }

                if useCentral {
                    showCentral(in: scene) { vc in
                        let request = HighlightRequest(uuid: uuidString, open: true)
                        NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
                    }
                } else {
                    let n = scene.session.configuration.storyboard?.instantiateViewController(identifier: "DetailController") as! UINavigationController
                    let d = n.viewControllers.first as! DetailController
                    d.item = item
                    scene.windows.first?.rootViewController = n
                }
                return
            }
            
        case kGladysStartPasteShortcutActivity:
            showCentral(in: scene) { _ in NotificationCenter.default.post(name: .ForcePasteRequest, object: nil) }
            return

        case kGladysStartSearchShortcutActivity:
            showCentral(in: scene) { _ in NotificationCenter.default.post(name: .StartSearchRequest, object: nil) }
            return

        case CSSearchableItemActionType:
            if let userActivity = userActivity, let itemIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                let request = HighlightRequest(uuid: itemIdentifier)
                showCentral(in: scene) { _ in NotificationCenter.default.post(name: .HighlightItemRequested, object: request) }
                return
            }

        case CSQueryContinuationActionType:
            if let userActivity = userActivity, let searchQuery = userActivity.userInfo?[CSSearchQueryString] as? String {
                showCentral(in: scene) { _ in NotificationCenter.default.post(name: .StartSearchRequest, object: searchQuery) }
                return
            }

        default:
            showCentral(in: scene)
            return
        }
        
        log("Could not process current activity, ignoring")
        UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
    }
    
    private func showCentral(in scene: UIWindowScene, restoringLabels labels: Set<String>? = nil, completion: ((ViewController)->Void)? = nil) {
        let s = scene.session
        let v: ViewController
        let replacing: Bool
        if let n = scene.windows.first?.rootViewController as? UINavigationController, let vc = n.viewControllers.first as? ViewController {
            v = vc
            replacing = false
        } else {
            let n = s.configuration.storyboard?.instantiateViewController(identifier: "Central") as! UINavigationController
            v = n.viewControllers.first as! ViewController
            replacing = true
        }
        
        let filter = s.associatedFilter
        if let labels = labels {
            filter.enableLabelsByName(labels)
        }
        v.filter = filter
        if replacing {
            v.onLoad = completion
            scene.windows.first?.rootViewController = v.navigationController
        } else {
            completion?(v)
        }
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
            CloudManager.opportunisticSyncIfNeeded(isStartup: false)
        }
        checkWindowCount()
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        checkWindowCount()
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        checkWindowCount()
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        checkWindowCount()
    }
    
    static var openCount = 0
    private func checkWindowCount() {
        let count = UIApplication.shared.connectedScenes.filter { $0.activationState != .background }.count
        if SceneDelegate.openCount == 1 && count != 1 {
            SceneDelegate.openCount = count
            NotificationCenter.default.post(name: .MultipleWindowModeChange, object: true)
        } else if SceneDelegate.openCount != 1 && count == 1 {
            SceneDelegate.openCount = count
            NotificationCenter.default.post(name: .MultipleWindowModeChange, object: false)
        }
    }
}
