import CloudKit
import GladysCommon
import GladysUI
import GladysUIKit
import UIKit

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

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let forceMainWindow = !UIApplication.shared.supportsMultipleScenes
        if let shortcut = connectionOptions.shortcutItem, let scene = scene as? UIWindowScene {
            Task {
                _ = await windowScene(scene, performActionFor: shortcut)
            }
        } else {
            Singleton.shared.handleActivity(connectionOptions.userActivities.first ?? session.stateRestorationActivity, in: scene, forceMainWindow: forceMainWindow)
            updateWindowCount()
        }
    }

    func sceneDidDisconnect(_: UIScene) {
        updateWindowCount()
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        if shortcutItem.type.hasSuffix(".Search") {
            Singleton.shared.boot(with: NSUserActivity(activityType: kGladysStartSearchShortcutActivity), in: windowScene)
            return true

        } else if shortcutItem.type.hasSuffix(".Paste") {
            Singleton.shared.boot(with: NSUserActivity(activityType: kGladysStartPasteShortcutActivity), in: windowScene)
            return true
        }
        return false
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
        updateWindowCount()
        log("Scene foregrounded")
        if let vc = scene.mainController {
            vc.sceneForegrounded()
        }
    }

    func sceneWillResignActive(_: UIScene) {
        updateWindowCount()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        updateWindowCount()
        if let vc = scene.mainController {
            vc.sceneBackgrounded()
        }
        log("Scene backgrounded")
    }

    func sceneDidBecomeActive(_: UIScene) {
        updateWindowCount()
        Model.updateBadge()
    }

    private func updateWindowCount() {
        var count = 0
        for scene in UIApplication.shared.connectedScenes where scene.activationState != .background {
            count += 1
        }
        Singleton.shared.openCount = count
        if let c = currentWindow {
            Singleton.shared.lastUsedWindow = c
        }
    }

    func windowScene(_: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { // need to wait for the UI to show up first, if the app is being launched and not foregrounded
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            do {
                try await CloudManager.acceptShare(cloudKitShareMetadata)
            } catch {
                await genericAlert(title: "Failed to accept item", message: error.localizedDescription)
            }
        }
    }
}
