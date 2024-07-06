import Foundation
import GladysCommon
import GladysUI
import Maintini
import MapKit
import UIKit
import WatchConnectivity

extension MKMapItem: @retroactive @unchecked Sendable {}

final class WatchDelegate: NSObject, WCSessionDelegate {
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
            HighlightRequest.send(uuid: uuid, extraAction: .open)
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
        Maintini.startMaintaining()
        defer {
            Maintini.endMaintaining()
        }

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
        return await task.value
    }

    func updateContext() async {
        let session = WCSession.default
        guard session.isReachable, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        if let context = await buildContext() {
            session.transferUserInfo(context)
            log("Updated watch context")
        }
    }
}
