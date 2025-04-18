import CoreSpotlight
import GladysCommon
import GladysUI
import GladysUIKit
import UIKit

@MainActor
final class Singleton {
    static let shared = Singleton()

    var componentDropActiveFromDetailView: DetailController?

    weak var lastUsedWindow: UIWindow?

    private func setBadgeCount(to count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    func setup() {
        Model.registerStateHandler()
        Model.badgeHandler = { [weak self] in
            guard let self else { return }
            if PersistedOptions.badgeIconWithItemCount, let count = lastUsedWindow?.associatedFilter?.filteredDrops.count {
                log("Updating app badge to show item count (\(count))")
                setBadgeCount(to: count)
            } else {
                log("Updating app badge to clear")
                setBadgeCount(to: 0)
            }
        }

        do {
            try Model.setup()
        } catch {
            Task {
                await genericAlert(title: "Loading Error", message: error.localizedDescription)
                abort()
            }
            return
        }

        CallbackSupport.setupCallbackSupport()

        Task {
            let name = await Reachability.shared.statusName
            log("Initial reachability status: \(name)")
        }

        notifications(for: .ModelDataUpdated) { _ in
            let backgroundSessions = UIApplication.shared.openSessions.filter { $0.scene?.activationState == .background }
            for session in backgroundSessions {
                UIApplication.shared.requestSceneSessionRefresh(session)
            }
            if PersistedOptions.extensionRequestedSync { // in case extension requested a sync but it didn't happen for whatever reason, let's do it now
                PersistedOptions.extensionRequestedSync = false
                do {
                    try await CloudManager.opportunisticSyncIfNeeded(force: true)
                } catch {
                    log("Error in extension triggered sync: \(error.localizedDescription)")
                }
            }
        }

        notifications(for: UIApplication.willEnterForegroundNotification) { _ in
            log("App foregrounded")
            do {
                try await CloudManager.opportunisticSyncIfNeeded()
            } catch {
                log("Error in forgrounding triggered sync: \(error.localizedDescription)")
            }
        }

        notifications(for: UIApplication.didEnterBackgroundNotification) { _ in
            log("App backgrounded")
            Model.lockUnlockedItems()
        }

        notifications(for: .IngestComplete) { object in
            if !DropStore.ingestingItems {
                await Model.save()
            } else if let item = object as? ArchivedItem {
                Model.commitItem(item: item)
            }
        }

        Coordination.beginMonitoringChanges()

        let mirrorPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Mirrored Files")
        if FileManager.default.fileExists(atPath: mirrorPath.path) {
            try? FileManager.default.removeItem(at: mirrorPath)
        }

        Task {
            await TipJar.shared.setupIfNeeded()
        }
    }

    func handleActivity(_ userActivity: NSUserActivity?, in scene: UIScene, forceMainWindow: Bool) {
        guard let scene = scene as? UIWindowScene else { return }

        if userActivity != nil {
            scene.session.stateRestorationActivity = userActivity
        }

        switch userActivity?.activityType {
        case kGladysMainListActivity:
            let searchText = userActivity?.userInfo?[kGladysMainViewSearchText] as? String
            let displayMode = userActivity?.userInfo?[kGladysMainViewDisplayMode] as? Int

            let legacyLabelList: Set<String>? = if let list = userActivity?.userInfo?["kGladysMainViewLabelList"] as? [String], list.isPopulated {
                Set(list)
            } else {
                nil
            }

            var labels: [Filter.Toggle]?
            if let labelData = userActivity?.userInfo?[kGladysMainViewSections] as? Data, let labelList = try? JSONDecoder().decode([Filter.Toggle].self, from: labelData) {
                labels = labelList
            }

            _ = showMainWindow(in: scene, restoringSearch: searchText, restoringDisplayMode: displayMode, labelList: labels, legacyLabelList: legacyLabelList)
            return

        case kGladysQuicklookActivity:
            if
                let userActivity,
                let userInfo = userActivity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String {
                guard let item = DropStore.item(uuid: uuidString) else {
                    _ = showMainWindow(in: scene)
                    Task {
                        await genericAlert(title: "Not Found", message: "This item was not found")
                    }
                    return
                }

                Task {
                    let child: Component? = if let childUuid = userInfo[kGladysDetailViewingActivityItemTypeUuid] as? String {
                        DropStore.component(uuid: childUuid)
                    } else {
                        item.previewableTypeItem
                    }
                    if forceMainWindow {
                        _ = showMainWindow(in: scene)
                        HighlightRequest.send(uuid: uuidString, extraAction: .preview(child?.uuid.uuidString))

                    } else if let child,
                              let q = child.quickLook() {
                        let n = GladysNavController(rootViewController: q)
                        replaceRootVc(in: scene, with: n)
                    }
                }
                return
            }

        case kGladysDetailViewingActivity:
            if
                let userActivity,
                let userInfo = userActivity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String {
                guard let item = DropStore.item(uuid: uuidString) else {
                    _ = showMainWindow(in: scene)
                    Task {
                        await genericAlert(title: "Not Found", message: "This item was not found")
                    }
                    return
                }

                if forceMainWindow {
                    _ = showMainWindow(in: scene)
                    HighlightRequest.send(uuid: uuidString, extraAction: .open)
                } else {
                    let n = scene.session.configuration.storyboard?.instantiateViewController(identifier: "DetailController") as! UINavigationController
                    let d = n.viewControllers.first as! DetailController
                    d.item = item
                    replaceRootVc(in: scene, with: n)
                }
                return
            }

        case kGladysStartPasteShortcutActivity:
            let v = showMainWindow(in: scene)
            Task {
                await v.forcePaste()
            }
            return

        case kGladysStartSearchShortcutActivity:
            let v = showMainWindow(in: scene)
            Task {
                await v.startSearch(nil)
            }
            return

        case CSSearchableItemActionType:
            if let userActivity, let itemIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                _ = showMainWindow(in: scene)
                HighlightRequest.send(uuid: itemIdentifier, extraAction: .none)
                return
            }

        case CSQueryContinuationActionType:
            if let userActivity, let searchQuery = userActivity.userInfo?[CSSearchQueryString] as? String {
                let v = showMainWindow(in: scene)
                Task {
                    await v.startSearch(searchQuery)
                }
                return
            }

        default:
            _ = showMainWindow(in: scene)
            return
        }

        if UIApplication.shared.supportsMultipleScenes {
            log("Could not process current activity, ignoring")
            UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
        }
    }

    @discardableResult
    private func showMainWindow(in scene: UIWindowScene, restoringSearch: String? = nil, restoringDisplayMode: Int? = nil, labelList: [Filter.Toggle]? = nil, legacyLabelList: Set<String>? = nil) -> ViewController {
        let sceneSession = scene.session

        let filter = sceneSession.associatedFilter
        if let labelList {
            filter.applyLabelConfig(from: labelList)

        } else if let legacyLabelList {
            filter.enableLabelsByName(legacyLabelList)
        }

        if let search = restoringSearch, search.isPopulated {
            filter.text = search
        }

        if let modeNumber = restoringDisplayMode, let mode = Filter.GroupingMode(rawValue: modeNumber) {
            filter.groupingMode = mode
        }

        let v: ViewController
        if let vc = scene.mainController {
            v = vc
            v.filter = filter
        } else {
            let n = sceneSession.configuration.storyboard?.instantiateViewController(identifier: "Central") as! UINavigationController
            v = n.viewControllers.first as! ViewController
            v.filter = filter
            replaceRootVc(in: scene, with: v.navigationController)
        }

        return v
    }

    private func replaceRootVc(in scene: UIWindowScene, with vc: UIViewController?) {
        guard let vc else { return }
        if !Model.brokenMode {
            scene.windows.first?.rootViewController = vc
        }
    }

    func boot(with activity: NSUserActivity?, in scene: UIScene?) {
        if UIApplication.shared.supportsMultipleScenes {
            let centralSession = UIApplication.shared.openSessions.first { $0.isMainWindow }
            let options = UIScene.ActivationRequestOptions()
            options.requestingScene = scene
            UIApplication.shared.requestSceneSessionActivation(centralSession, userActivity: activity, options: options) { error in
                log("Error requesting new scene: \(error)")
            }
        } else if let scene {
            handleActivity(activity, in: scene, forceMainWindow: true)
        } else {
            // in theory this should never happen, leave the UI as-is
        }
    }

    var openCount = 0 {
        didSet {
            if openCount == 1, oldValue != 1 {
                sendNotification(name: .MultipleWindowModeChange, object: true)
            } else if openCount != 1, oldValue == 1 {
                sendNotification(name: .MultipleWindowModeChange, object: false)
            }
        }
    }

    func openUrl(_ url: URL, options: UIScene.OpenURLOptions, in scene: UIWindowScene) {
        if let c = url.host, c == "inspect-item", let itemId = url.pathComponents.last {
            let activity = NSUserActivity(activityType: CSSearchableItemActionType)
            activity.addUserInfoEntries(from: [CSSearchableItemActivityIdentifier: itemId])
            Task {
                Singleton.shared.boot(with: activity, in: scene)
            }

        } else if url.host == nil { // just opening
            if url.isFileURL, url.pathExtension.lowercased() == "gladysarchive", let presenter = scene.windows.first?.alertPresenter {
                let a = UIAlertController(title: "Import Archive?", message: "Import items from \"\(url.deletingPathExtension().lastPathComponent)\"?", preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "Import", style: .destructive) { _ in
                    let securityScoped = options.openInPlace ? url.startAccessingSecurityScopedResource() : false
                    Task {
                        do {
                            try await ImportExport.importArchive(from: url, removingOriginal: !options.openInPlace)
                        } catch {
                            await genericAlert(title: "Could not import data", message: error.localizedDescription)
                        }
                        if securityScoped {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                })
                a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                presenter.present(a, animated: true)
            }

        } else if !PersistedOptions.blockGladysUrlRequests {
            _ = CallbackSupport.handlePossibleCallbackURL(url: url)
        }
    }
}
