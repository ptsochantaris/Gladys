import CloudKit
import CoreSpotlight
import GladysFramework
import MapKit
import UIKit
import WatchConnectivity

private class WatchDelegate: NSObject, WCSessionDelegate {
    override init() {
        super.init()
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {}

    func sessionReachabilityDidChange(_: WCSession) {}

    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_: WCSession) {}

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.handle(message: message, replyHandler: { _ in })
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            self.handle(message: message, replyHandler: replyHandler)
        }
    }

    @MainActor
    private func handle(message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if let uuid = message["view"] as? String {
            let request = HighlightRequest(uuid: uuid, open: true)
            NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
            DispatchQueue.global(qos: .background).async {
                replyHandler([:])
            }

        } else if let uuid = message["moveToTop"] as? String, let item = Model.item(uuid: uuid) {
            Model.sendToTop(items: [item])
            DispatchQueue.global(qos: .background).async {
                replyHandler([:])
            }

        } else if let uuid = message["delete"] as? String, let item = Model.item(uuid: uuid) {
            Model.delete(items: [item])
            DispatchQueue.global(qos: .background).async {
                replyHandler([:])
            }

        } else if let uuid = message["copy"] as? String, let item = Model.item(uuid: uuid) {
            item.copyToPasteboard()
            DispatchQueue.global(qos: .background).async {
                replyHandler([:])
            }

        } else if let command = message["update"] as? String, command == "full" {
            buildContext { context in
                replyHandler(context ?? [:])
            }

        } else if let uuid = message["image"] as? String, let item = Model.item(uuid: uuid) {
            let W = message["width"] as! CGFloat
            let H = message["height"] as! CGFloat
            let size = CGSize(width: W, height: H)

            let mode = item.displayMode
            if mode == .center, let backgroundInfoObject = item.backgroundInfoObject {
                if let color = backgroundInfoObject as? UIColor {
                    let icon = UIGraphicsImageRenderer(size: size).image { context in
                        context.cgContext.setFillColor(color.cgColor)
                        context.fill(CGRect(origin: .zero, size: size))
                    }
                    proceedWithImage(icon, size: nil, mode: .center, replyHandler: replyHandler)

                } else if let mapItem = backgroundInfoObject as? MKMapItem {
                    handleMapItemPreview(mapItem: mapItem, size: size, fallbackIcon: item.displayIcon, replyHandler: replyHandler)

                } else {
                    proceedWithImage(item.displayIcon, size: size, mode: .center, replyHandler: replyHandler)
                }
            } else {
                proceedWithImage(item.displayIcon, size: size, mode: mode, replyHandler: replyHandler)
            }

        } else {
            DispatchQueue.global(qos: .background).async {
                replyHandler([:])
            }
        }
    }

    private func handleMapItemPreview(mapItem: MKMapItem, size: CGSize, fallbackIcon: UIImage, replyHandler: @escaping ([String: Any]) -> Void) {
        Task {
            do {
                let options = Images.SnapshotOptions(coordinate: mapItem.placemark.coordinate, range: 150, outputSize: size)
                let img = try await Images.shared.mapSnapshot(with: options)
                self.proceedWithImage(img, size: size, mode: .fill, replyHandler: replyHandler)
            } catch {
                self.proceedWithImage(fallbackIcon, size: size, mode: .center, replyHandler: replyHandler)
            }
        }
    }

    private func proceedWithImage(_ icon: UIImage, size: CGSize?, mode: ArchivedDropItemDisplayType, replyHandler: @escaping ([String: Any]) -> Void) {
        Task.detached {
            let data: Data
            if let size = size {
                if mode == .center || mode == .circle {
                    let scaledImage = icon.limited(to: size, limitTo: 0.2, singleScale: true)
                    data = scaledImage.pngData()!
                } else {
                    let scaledImage = icon.limited(to: size, limitTo: 1.0, singleScale: true)
                    data = scaledImage.jpegData(compressionQuality: 0.6)!
                }
            } else {
                data = icon.pngData()!
            }
            replyHandler(["image": data])
        }
    }

    private func buildContext(completion: @escaping ([String: Any]?) -> Void) {
        BackgroundTask.registerForBackground()

        DispatchQueue.main.async {
            let total = Model.drops.count
            let items = Model.drops.prefix(100).map(\.watchItem)
            DispatchQueue.global(qos: .background).async {
                if let compressedData = SafeArchiving.archive(items)?.data(operation: .compress) {
                    log("Built watch context")
                    completion(["total": total, "dropList": compressedData])
                } else {
                    log("Failed to build watch context")
                    completion(nil)
                }
                BackgroundTask.unregisterForBackground()
            }
        }
    }

    fileprivate func updateContext() {
        let session = WCSession.default
        guard session.isReachable, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        buildContext { context in
            if let context = context {
                session.transferUserInfo(context)
                log("Updated watch context")
            }
        }
    }
}

extension Model.SortOption {
    var ascendingIcon: UIImage? {
        switch self {
        case .label: return UIImage(systemName: "line.horizontal.3")
        case .dateAdded: return UIImage(systemName: "calendar")
        case .dateModified: return UIImage(systemName: "calendar.badge.exclamationmark")
        case .note: return UIImage(systemName: "rectangle.and.pencil.and.ellipsis")
        case .title: return UIImage(systemName: "arrow.down")
        case .size: return UIImage(systemName: "arrow.up.left.and.arrow.down.right.circle")
        }
    }

    var descendingIcon: UIImage? {
        switch self {
        case .label: return UIImage(systemName: "line.horizontal.3")
        case .dateAdded: return UIImage(systemName: "calendar")
        case .dateModified: return UIImage(systemName: "calendar.badge.exclamationmark")
        case .note: return UIImage(systemName: "rectangle.and.pencil.and.ellipsis")
        case .title: return UIImage(systemName: "arrow.up")
        case .size: return UIImage(systemName: "arrow.down.forward.and.arrow.up.backward.circle")
        }
    }
}

extension UISceneSession {
    var associatedFilter: Filter {
        if let existing = userInfo?[kGladysMainFilter] as? Filter {
            return existing
        }
        let newFilter = Filter()
        if userInfo == nil {
            userInfo = [String: Any]()
        }
        userInfo![kGladysMainFilter] = newFilter
        return newFilter
    }
}

extension UIView {
    var associatedFilter: Filter? {
        let w = (self as? UIWindow) ?? window
        return w?.windowScene?.session.associatedFilter
    }
}

extension Model {
    private static var saveOverlap = 0
    private static var registeredForBackground = false

    private static var watchDelegate: WatchDelegate?

    static var coordinator: NSFileCoordinator {
        NSFileCoordinator(filePresenter: filePresenter)
    }

    static func prepareToSave() {
        saveOverlap += 1
        if !registeredForBackground {
            registeredForBackground = true
            BackgroundTask.registerForBackground()
            // log("Starting save queue background task")
        }
    }

    static func startupComplete() {
        trimTemporaryDirectory()

        if WCSession.isSupported() {
            watchDelegate = WatchDelegate()
        }
    }

    static func saveComplete(wasIndexOnly: Bool) {
        if wasIndexOnly {
            saveDone()
        } else {
            saveOverlap -= 1
            if saveOverlap == 0 {
                if PersistedOptions.mirrorFilesToDocuments {
                    Task {
                        await updateMirror()
                        saveDone()
                    }
                } else {
                    saveDone()
                }
            }
        }
    }

    private static func saveDone() {
        watchDelegate?.updateContext()

        if saveIsDueToSyncFetch, !CloudManager.syncDirty {
            saveIsDueToSyncFetch = false
            log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
        } else {
            if CloudManager.syncDirty {
                log("A sync had been requested while syncing, evaluating another sync")
            }
            CloudManager.syncAfterSaveIfNeeded()
        }

        if registeredForBackground {
            registeredForBackground = false
            BackgroundTask.unregisterForBackground()
        }
    }

    private static var foregroundObserver: NSObjectProtocol?
    private static var backgroundObserver: NSObjectProtocol?

    static func beginMonitoringChanges() {
        let n = NotificationCenter.default
        foregroundObserver = n.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            foregrounded()
        }
        backgroundObserver = n.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            backgrounded()
        }
        foregrounded()
    }

    private static let filePresenter = ModelFilePresenter()

    private static func foregrounded() {
        NSFileCoordinator.addFilePresenter(filePresenter)
        reloadDataIfNeeded()
    }

    private static func backgrounded() {
        NSFileCoordinator.removeFilePresenter(filePresenter)
    }

    static func createMirror() async {
        log("Creating file mirror")
        drops.forEach { $0.flags.remove(.skipMirrorAtNextSave) }
        await runMirror()
    }

    static func updateMirror() async {
        log("Updating file mirror")
        await runMirror()
    }

    @MainActor
    private static func runMirror() async {
        let itemsToMirror: ContiguousArray = drops.filter(\.goodToSave)
        BackgroundTask.registerForBackground()
        await MirrorManager.mirrorToFiles(from: itemsToMirror, andPruneOthers: true)
        BackgroundTask.unregisterForBackground()
    }

    @MainActor
    static func scanForMirrorChanges() async {
        BackgroundTask.registerForBackground()
        let itemsToMirror: ContiguousArray = drops.filter(\.goodToSave)
        await MirrorManager.scanForMirrorChanges(items: itemsToMirror)
        BackgroundTask.unregisterForBackground()
    }

    static func deleteMirror() async {
        await MirrorManager.removeMirrorIfNeeded()
    }

    static func _updateBadge() {
        if PersistedOptions.badgeIconWithItemCount, let count = lastUsedWindow?.associatedFilter?.filteredDrops.count {
            log("Updating app badge to show item count (\(count))")
            UIApplication.shared.applicationIconBadgeNumber = count
        } else {
            log("Updating app badge to clear")
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
}
