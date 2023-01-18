import CoreSpotlight
import UIKit
import GladysCommon

@MainActor
final class Singleton {
    static let shared = Singleton()

    var componentDropActiveFromDetailView: DetailController?

    func setup() {
        Model.setup()

        CallbackSupport.setupCallbackSupport()

        Task {
            let name = await reachability.statusName
            log("Initial reachability status: \(name)")
        }

        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(modelDataUpdate), name: .ModelDataUpdated, object: nil)
        n.addObserver(self, selector: #selector(foregrounded), name: UIApplication.willEnterForegroundNotification, object: nil)
        n.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
        n.addObserver(self, selector: #selector(ingestStart), name: .IngestStart, object: nil)
        n.addObserver(self, selector: #selector(ingestComplete(_:)), name: .IngestComplete, object: nil)

        Model.beginMonitoringChanges() // will reload data as well
        Task {
            await Model.detectExternalChanges()
        }

        let mirrorPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Mirrored Files")
        if FileManager.default.fileExists(atPath: mirrorPath.path) {
            try? FileManager.default.removeItem(at: mirrorPath)
        }
    }

    @objc private func foregrounded() {
        if UIApplication.shared.applicationState == .background {
            // foregrounding, not including app launch
            log("App foregrounded")
            Task {
                do {
                    try await CloudManager.opportunisticSyncIfNeeded()
                } catch {
                    log("Error in forgrounding triggered sync: \(error.finalDescription)")
                }
            }
        }
    }

    @objc private func backgrounded() {
        log("App backgrounded")
        Model.lockUnlockedItems()
    }

    @objc private func modelDataUpdate() {
        let backgroundSessions = UIApplication.shared.openSessions.filter { $0.scene?.activationState == .background }
        Task {
            await Model.detectExternalChanges()
            for session in backgroundSessions {
                UIApplication.shared.requestSceneSessionRefresh(session)
            }
            if PersistedOptions.extensionRequestedSync { // in case extension requested a sync but it didn't happen for whatever reason, let's do it now
                PersistedOptions.extensionRequestedSync = false
                do {
                    try await CloudManager.opportunisticSyncIfNeeded(force: true)
                } catch {
                    log("Error in extension triggered sync: \(error.finalDescription)")
                }
            }
        }
    }

    @objc private func ingestStart() {
        BackgroundTask.registerForBackground()
    }

    @objc private func ingestComplete(_ notification: Notification) {
        guard let item = notification.object as? ArchivedItem else { return }
        if Model.doneIngesting {
            Model.save()
        } else {
            Model.commitItem(item: item)
        }
        BackgroundTask.unregisterForBackground()
    }

    func handleActivity(_ userActivity: NSUserActivity?, in scene: UIScene, forceMainWindow: Bool) async {
        guard let scene = scene as? UIWindowScene else { return }

        scene.session.stateRestorationActivity = userActivity

        switch userActivity?.activityType {
        case kGladysMainListActivity:
            let searchText = userActivity?.userInfo?[kGladysMainViewSearchText] as? String
            let displayMode = userActivity?.userInfo?[kGladysMainViewDisplayMode] as? Int

            let legacyLabelList: Set<String>?
            if let list = userActivity?.userInfo?["kGladysMainViewLabelList"] as? [String], !list.isEmpty {
                legacyLabelList = Set(list)
            } else {
                legacyLabelList = nil
            }

            var labels: [Filter.Toggle]?
            if let labelData = userActivity?.userInfo?[kGladysMainViewSections] as? Data, let labelList = try? JSONDecoder().decode([Filter.Toggle].self, from: labelData) {
                labels = labelList
            }

            _ = await showMainWindow(in: scene, restoringSearch: searchText, restoringDisplayMode: displayMode, labelList: labels, legacyLabelList: legacyLabelList)
            return

        case kGladysQuicklookActivity:
            if
                let userActivity,
                let userInfo = userActivity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String {
                guard let item = Model.item(uuid: uuidString) else {
                    _ = await showMainWindow(in: scene)
                    await genericAlert(title: "Not Found", message: "This item was not found")
                    return
                }

                let child: Component?
                if let childUuid = userInfo[kGladysDetailViewingActivityItemTypeUuid] as? String {
                    child = await Model.component(uuid: childUuid)
                } else {
                    child = item.previewableTypeItem
                }
                if forceMainWindow {
                    let v = await showMainWindow(in: scene)
                    let request = HighlightRequest(uuid: uuidString, extraAction: .preview(child?.uuid.uuidString))
                    await v.highlightItem(request)
                    return

                } else if let child {
                    if let q = child.quickLook() {
                        let n = GladysNavController(rootViewController: q)
                        scene.windows.first?.rootViewController = n
                    }
                    return
                }
            }

        case kGladysDetailViewingActivity:
            if
                let userActivity,
                let userInfo = userActivity.userInfo,
                let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String {
                guard let item = Model.item(uuid: uuidString) else {
                    _ = await showMainWindow(in: scene)
                    await genericAlert(title: "Not Found", message: "This item was not found")
                    return
                }

                if forceMainWindow {
                    let v = await showMainWindow(in: scene)
                    let request = HighlightRequest(uuid: uuidString, extraAction: .open)
                    await v.highlightItem(request)

                } else {
                    let n = scene.session.configuration.storyboard?.instantiateViewController(identifier: "DetailController") as! UINavigationController
                    let d = n.viewControllers.first as! DetailController
                    d.item = item
                    scene.windows.first?.rootViewController = n
                }
                return
            }

        case kGladysStartPasteShortcutActivity:
            let v = await showMainWindow(in: scene)
            await v.forcePaste()
            return

        case kGladysStartSearchShortcutActivity:
            let v = await showMainWindow(in: scene)
            v.startSearch(nil)
            return

        case CSSearchableItemActionType:
            if let userActivity, let itemIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                let request = HighlightRequest(uuid: itemIdentifier, extraAction: .none)
                let v = await showMainWindow(in: scene)
                await v.highlightItem(request)
                return
            }

        case CSQueryContinuationActionType:
            if let userActivity, let searchQuery = userActivity.userInfo?[CSSearchQueryString] as? String {
                let v = await showMainWindow(in: scene)
                v.startSearch(searchQuery)
                return
            }

        default:
            _ = await showMainWindow(in: scene)
            return
        }

        if UIApplication.shared.supportsMultipleScenes {
            log("Could not process current activity, ignoring")
            UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
        }
    }

    @discardableResult
    private func showMainWindow(in scene: UIWindowScene, restoringSearch: String? = nil, restoringDisplayMode: Int? = nil, labelList: [Filter.Toggle]? = nil, legacyLabelList: Set<String>? = nil) async -> ViewController {
        let s = scene.session
        let v: ViewController
        let replacing: Bool
        if let vc = scene.mainController {
            v = vc
            replacing = false
        } else {
            let n = s.configuration.storyboard?.instantiateViewController(identifier: "Central") as! UINavigationController
            v = n.viewControllers.first as! ViewController
            replacing = true
        }

        let filter = s.associatedFilter
        if let labelList {
            filter.applyLabelConfig(from: labelList)

        } else if let legacyLabelList {
            filter.enableLabelsByName(legacyLabelList)
        }

        if let search = restoringSearch, !search.isEmpty {
            filter.text = search
        }
        if let modeNumber = restoringDisplayMode, let mode = Filter.GroupingMode(rawValue: modeNumber) {
            filter.groupingMode = mode
        }

        v.filter = filter
        filter.delegate = v
        if replacing {
            scene.windows.first?.rootViewController = v.navigationController
            await v.onLoadTask?.wait()
        }
        return v
    }

    func boot(with activity: NSUserActivity?, in scene: UIScene?) async {
        if UIApplication.shared.supportsMultipleScenes {
            let centralSession = UIApplication.shared.openSessions.first { $0.isMainWindow }
            let options = UIScene.ActivationRequestOptions()
            options.requestingScene = scene
            UIApplication.shared.requestSceneSessionActivation(centralSession, userActivity: activity, options: options) { error in
                log("Error requesting new scene: \(error)")
            }
        } else if let scene {
            await handleActivity(activity, in: scene, forceMainWindow: true)
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
                await Singleton.shared.boot(with: activity, in: scene)
            }

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
                        Task {
                            await genericAlert(title: "Could not import data", message: error.finalDescription)
                        }
                    }
                    if securityScoped {
                        url.stopAccessingSecurityScopedResource()
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
