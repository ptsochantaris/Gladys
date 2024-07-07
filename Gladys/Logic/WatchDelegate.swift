import Foundation
import GladysCommon
import GladysUI
import Maintini
import MapKit
import UIKit
import WatchConnectivity

extension MKMapItem: @retroactive @unchecked Sendable {}

@MainActor
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

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        let sendableMessage: [String: TextOrNumber] = message.compactMapValues { TextOrNumber(value: $0) }
        Task.detached { [weak self] in
            guard let self else { return }
            _ = await handle(message: sendableMessage)
        }
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let sendableMessage: [String: TextOrNumber] = message.compactMapValues { TextOrNumber(value: $0) }
        Task.detached { [weak self] in
            guard let self else { return }
            let data = await handle(message: sendableMessage)
            replyHandler(data)
        }
    }

    private func handle(message: [String: TextOrNumber]) async -> [String: Sendable] {
        if let uuid = message["image"]?.asText, let item = DropStore.item(uuid: uuid) {
            guard let W = message["width"]?.asNumber, let H = message["height"]?.asNumber else {
                return [:]
            }

            let size = CGSize(width: W, height: H)

            let mode = item.displayMode
            let data: Data
            if mode == .center, let backgroundInfoObject = item.backgroundInfoObject {
                if let color = backgroundInfoObject as? UIColor {
                    let icon = UIGraphicsImageRenderer(size: size).image { context in
                        context.cgContext.setFillColor(color.cgColor)
                        context.fill(CGRect(origin: .zero, size: size))
                    }
                    data = Self.proceedWithImage(icon, size: nil, mode: .center)

                } else if let mapItem = backgroundInfoObject as? MKMapItem {
                    data = await Self.handleMapItemPreview(mapItem: mapItem, size: size, fallbackIcon: item.displayIcon)

                } else {
                    data = await Self.proceedWithImage(item.displayIcon, size: size, mode: .center)
                }
            } else {
                data = await Self.proceedWithImage(item.displayIcon, size: size, mode: mode)
            }
            return ["image": data]
        }

        if let command = message["update"]?.asText, command == "full", let context = await buildContext() {
            return context
        }

        if let uuid = message["view"]?.asText {
            HighlightRequest.send(uuid: uuid, extraAction: .open)

        } else if let uuid = message["moveToTop"]?.asText, let item = DropStore.item(uuid: uuid) {
            Model.sendToTop(items: [item])

        } else if let uuid = message["delete"]?.asText, let item = DropStore.item(uuid: uuid) {
            Model.delete(items: [item])

        } else if let uuid = message["copy"]?.asText, let item = DropStore.item(uuid: uuid) {
            item.copyToPasteboard()
        }

        return [:]
    }

    private nonisolated static func handleMapItemPreview(mapItem: MKMapItem, size: CGSize, fallbackIcon: UIImage) async -> Data {
        do {
            let options = Images.SnapshotOptions(coordinate: mapItem.placemark.coordinate, range: 150, outputSize: size)
            let img = try await Images.shared.mapSnapshot(with: options)
            return proceedWithImage(img, size: size, mode: .fill)
        } catch {
            return proceedWithImage(fallbackIcon, size: size, mode: .center)
        }
    }

    private nonisolated static func proceedWithImage(_ icon: UIImage, size: CGSize?, mode: ArchivedDropItemDisplayType) -> Data {
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

    private func buildContext() async -> [String: Sendable]? {
        Maintini.startMaintaining()
        defer {
            Maintini.endMaintaining()
        }

        let drops = DropStore.allDrops
        let total = drops.count
        let items = drops.prefix(100).map(\.watchItem)
        let task = Task<[String: Sendable]?, Never>.detached {
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
