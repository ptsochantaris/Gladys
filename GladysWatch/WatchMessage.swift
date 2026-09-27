import Foundation
import WatchConnectivity

extension WCSession: @retroactive @unchecked Sendable {}

nonisolated enum WatchMessage: Codable {
    struct ImageInfo: Codable {
        let id: String
        let width: CGFloat
        let height: CGFloat
    }

    struct DropInfo: Codable {
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
    func sendWatchMessage(_ message: WatchMessage) async throws -> WatchMessage? {
        guard let data = message.asData else {
            return nil
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WatchMessage?, Error>) in
            // Reply and error handlers arrive on a WatchConnectivity background queue
            sendMessageData(data) { @Sendable reply in
                let watchMessage = WatchMessage.parse(from: reply)
                continuation.resume(returning: watchMessage)
            } errorHandler: { @Sendable error in
                continuation.resume(throwing: error)
            }
        }
    }
}
