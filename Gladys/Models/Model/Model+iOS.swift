import CloudKit
import CoreSpotlight
import GladysCommon
import MapKit
import UIKit
import WatchConnectivity
import Intents

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
        Task { @MainActor in
            self.handle(message: message, replyHandler: { _ in })
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.handle(message: message, replyHandler: replyHandler)
        }
    }

    @MainActor
    private func handle(message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if let uuid = message["view"] as? String {
            let request = HighlightRequest(uuid: uuid, extraAction: .open)
            sendNotification(name: .HighlightItemRequested, object: request)
            Task.detached(priority: .background) {
                replyHandler([:])
            }

        } else if let uuid = message["moveToTop"] as? String, let item = DropStore.item(uuid: uuid) {
            Model.sendToTop(items: [item])
            Task.detached(priority: .background) {
                replyHandler([:])
            }

        } else if let uuid = message["delete"] as? String, let item = DropStore.item(uuid: uuid) {
            Model.delete(items: [item])
            Task.detached(priority: .background) {
                replyHandler([:])
            }

        } else if let uuid = message["copy"] as? String, let item = DropStore.item(uuid: uuid) {
            item.copyToPasteboard()
            Task.detached(priority: .background) {
                replyHandler([:])
            }

        } else if let command = message["update"] as? String, command == "full" {
            Task {
                let context = await buildContext()
                replyHandler(context ?? [:])
            }

        } else if let uuid = message["image"] as? String, let item = DropStore.item(uuid: uuid) {
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
            Task.detached(priority: .background) {
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
            if let size {
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

    @MainActor
    private func buildContext() async -> [String: Any]? {
        BackgroundTask.registerForBackground()

        let drops = DropStore.allDrops
        let total = drops.count
        let items = drops.prefix(100).map(\.watchItem)
        let task = Task<[String: Any]?, Never>.detached {
            if let compressedData = SafeArchiving.archive(items)?.data(operation: .compress) {
                log("Built watch context")
                return ["total": total, "dropList": compressedData]
            } else {
                log("Failed to build watch context")
                return nil
            }
        }
        let res = await task.value
        BackgroundTask.unregisterForBackground()
        return res
    }

    fileprivate func updateContext() async {
        let session = WCSession.default
        guard session.isReachable, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        if let context = await buildContext() {
            session.transferUserInfo(context)
            log("Updated watch context")
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
            userInfo = [kGladysMainFilter: newFilter]
        } else {
            userInfo![kGladysMainFilter] = newFilter
        }
        return newFilter
    }
}

final class ModelFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL? = itemsDirectoryUrl

    let presentedItemOperationQueue = OperationQueue()

    func presentedItemDidChange() {
        Task { @MainActor in
            if DropStore.doneIngesting {
                Model.reloadDataIfNeeded()
            }
        }
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

    nonisolated static var coordinator: NSFileCoordinator {
        NSFileCoordinator(filePresenter: filePresenter)
    }

    static func prepareToSave() {
        saveOverlap += 1
        if !registeredForBackground {
            registeredForBackground = true
            BackgroundTask.registerForBackground()
        }
    }

    static func startupComplete() {
        trimTemporaryDirectory()

        if WCSession.isSupported() {
            watchDelegate = WatchDelegate()
        }
    }

    static func saveIndexComplete() {
        saveDone()
    }

    static func saveComplete() {
        saveOverlap -= 1
        if saveOverlap > 0 {
            return
        }
        saveDone()
    }

    private static func saveDone() {
        if let wd = watchDelegate {
            Task {
                await wd.updateContext()
            }
        }

        Task {
            do {
                try await resyncIfNeeded()
            } catch {
                log("Error in sync after save: \(error.finalDescription)")
            }
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
        NSFileCoordinator.addFilePresenter(filePresenter)
    }

    private static let filePresenter = ModelFilePresenter()

    private static func foregrounded() {
        NSFileCoordinator.addFilePresenter(filePresenter)
        reloadDataIfNeeded()
    }

    private static func backgrounded() {
        NSFileCoordinator.removeFilePresenter(filePresenter)
    }

    static func _updateBadge() async {
        if PersistedOptions.badgeIconWithItemCount, let count = lastUsedWindow?.associatedFilter?.filteredDrops.count {
            log("Updating app badge to show item count (\(count))")
            UIApplication.shared.applicationIconBadgeNumber = count
        } else {
            log("Updating app badge to clear")
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
    
    @discardableResult
    static func pasteItems(from providers: [NSItemProvider], overrides: ImportOverrides?) -> PasteResult {
        if providers.isEmpty {
            return .noData
        }

        let currentFilter = currentWindow?.associatedFilter

        var items = [ArchivedItem]()
        var addedStuff = false
        for provider in providers { // separate item for each provider in the pasteboard
            for item in ArchivedItem.importData(providers: [provider], overrides: overrides) {
                if let currentFilter, currentFilter.isFilteringLabels, !PersistedOptions.dontAutoLabelNewItems {
                    item.labels = currentFilter.enabledLabelsForItems
                }
                DropStore.insert(drop: item, at: 0)
                items.append(item)
                addedStuff = true
            }
        }

        if addedStuff {
            _ = currentFilter?.update(signalUpdate: .animated)
        }

        return .success(items)
    }
    
    static var pasteIntent: PasteClipboardIntent {
        let intent = PasteClipboardIntent()
        intent.suggestedInvocationPhrase = "Paste in Gladys"
        return intent
    }

    static func clearLegacyIntents() {
        if #available(iOS 16, *) {
            INInteraction.deleteAll() // using app intents now
        }
    }

    static func donatePasteIntent() {
        if #available(iOS 16, *) {
            log("Will not donate SiriKit paste shortcut")
        } else {
            let interaction = INInteraction(intent: pasteIntent, response: nil)
            interaction.identifier = "paste-in-gladys"
            interaction.donate { error in
                if let error {
                    log("Error donating paste shortcut: \(error.localizedDescription)")
                } else {
                    log("Donated paste shortcut")
                }
            }
        }
    }
}
