import Foundation
import WatchConnectivity

extension WCSession: @retroactive @unchecked Sendable {}

enum WatchMessage: Sendable, Codable {
    struct ImageInfo: Sendable, Codable {
        let id: String
        let width: CGFloat
        let height: CGFloat
    }

    struct DropInfo: Sendable, Codable {
        let id: String
        let title: String
        let imageDate: Date
    }

    case imageRequest(ImageInfo), imageData(Data), view(String), copy(String), moveToTop(String), delete(String), updateRequest(full: Bool), ok, failure, contextReply([DropInfo], Int)

    static func parse(from data: Data) -> WatchMessage? {
        guard let uncompressed = data.data(operation: .decompress)
        else {
            return nil
        }
        return try? JSONDecoder().decode(WatchMessage.self, from: uncompressed)
    }

    var asData: Data? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return data.data(operation: .compress)
    }
}

extension WCSession {
    func sendWatchMessage(_ message: WatchMessage) async -> WatchMessage? {
        guard let data = message.asData else {
            return nil
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<WatchMessage?, Never>) in
            sendMessageData(data) {
                let watchMessage = WatchMessage.parse(from: $0)
                continuation.resume(returning: watchMessage)
            }
        }
    }
}
