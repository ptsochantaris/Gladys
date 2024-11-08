import Foundation
import GladysCommon
import GladysUI
import Maintini
import MapKit
import UIKit
import WatchConnectivity

final class WatchDelegate: NSObject, WCSessionDelegate {
    override init() {
        super.init()

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {}

    nonisolated func sessionReachabilityDidChange(_: WCSession) {}

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    nonisolated func sessionDidDeactivate(_: WCSession) {}

    private enum TextOrNumber {
        case text(String), number(CGFloat)

        init?(value: Any) {
            if let text = value as? String {
                self = .text(text)
            } else if let number = value as? CGFloat {
                self = .number(number)
            } else {
                return nil
            }
        }

        var asText: String? {
            if case let .text(string) = self {
                string
            } else {
                nil
            }
        }

        var asNumber: CGFloat? {
            if case let .number(value) = self {
                value
            } else {
                nil
            }
        }
    }

    nonisolated func session(_: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        guard let watchMessage = WatchMessage.parse(from: messageData) else {
            replyHandler(Data())
            return
        }

        nonisolated(unsafe) let handler = replyHandler
        Task { @MainActor in
            let replyData = await Self.handle(message: watchMessage).asData ?? Data()
            handler(replyData)
        }
    }

    @MainActor
    private static func handle(message: WatchMessage) async -> WatchMessage {
        switch message {
        case let .imageRequest(imageInfo):
            guard let item = DropStore.item(uuid: imageInfo.id) else {
                return .failure
            }

            let size = CGSize(width: imageInfo.width, height: imageInfo.height)

            let mode = item.displayMode
            let data: Data
            if mode == .center, let backgroundInfoObject = item.backgroundInfoObject {
                switch backgroundInfoObject.content {
                case let .color(color):
                    let icon = UIGraphicsImageRenderer(size: size).image { context in
                        context.cgContext.setFillColor(color.cgColor)
                        context.fill(CGRect(origin: .zero, size: size))
                    }
                    data = Self.proceedWithImage(icon, size: nil, mode: .center)

                case let .map(mapItem):
                    let icon = await item.displayIcon
                    data = await Self.handleMapItemPreview(mapItem: mapItem, size: size, fallbackIcon: icon)
                }
            } else {
                data = await Self.proceedWithImage(item.displayIcon, size: size, mode: mode)
            }
            return .imageData(data)

        case let .view(uuid):
            HighlightRequest.send(uuid: uuid, extraAction: .open)
            return .ok

        case let .copy(uuid):
            if let item = DropStore.item(uuid: uuid) {
                item.copyToPasteboard()
                return .ok
            } else {
                return .failure
            }

        case let .moveToTop(uuid):
            if let item = DropStore.item(uuid: uuid) {
                Model.sendToTop(items: [item])
                return .ok
            } else {
                return .failure
            }

        case let .delete(uuid):
            if let item = DropStore.item(uuid: uuid) {
                Model.delete(items: [item])
                return .ok
            } else {
                return .failure
            }

        case .updateRequest:
            return buildContext()

        case .contextReply, .failure, .imageData, .ok:
            return .failure
        }
    }

    private static func handleMapItemPreview(mapItem: MKMapItem, size: CGSize, fallbackIcon: UIImage) async -> Data {
        do {
            let options = Images.SnapshotOptions(coordinate: mapItem.placemark.coordinate, range: 150, outputSize: size)
            let img = try await Images.mapSnapshot(with: options)
            return proceedWithImage(img, size: size, mode: .fill)
        } catch {
            return proceedWithImage(fallbackIcon, size: size, mode: .center)
        }
    }

    private static func proceedWithImage(_ icon: UIImage, size: CGSize?, mode: ArchivedDropItemDisplayType) -> Data {
        if let size {
            if mode == .center || mode == .circle {
                let scaledImage = icon.limited(to: size, limitTo: 0.2, singleScale: true)
                return scaledImage.pngData()!
            } else {
                let scaledImage = icon.limited(to: size, limitTo: 1.0, singleScale: true)
                return scaledImage.jpegData(compressionQuality: 0.6)!
            }
        } else {
            return icon.pngData()!
        }
    }

    @MainActor
    private static func buildContext() -> WatchMessage {
        let drops = DropStore.allDrops
        let items = drops.prefix(100).map(\.watchItem)
        return .contextReply(items, drops.count)
    }

    @MainActor
    func updateContext() {
        let session = WCSession.default
        guard session.isReachable, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let context = Self.buildContext()
        Maintini.startMaintaining()
        Task {
            _ = try? await session.sendWatchMessage(context)
            Maintini.endMaintaining()
        }
        log("Updated watch context")
    }
}
