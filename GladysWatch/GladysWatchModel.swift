import GladysCommon
import WatchConnectivity

@MainActor
@Observable
final class GladysWatchModel: NSObject, WCSessionDelegate {
    var reportedCount = 0
    var dropList = [Drop]()

    static let shared = GladysWatchModel()

    enum State {
        case loading, empty, list
    }

    var state = State.loading

    private nonisolated func receivedInfo(message: WatchMessage?) {
        switch message {
        case let .contextReply(dropList, reportedCount):
            let drops = dropList.map { Drop(dropInfo: $0) }
            Task { @MainActor in
                self.reportedCount = reportedCount
                self.dropList = drops
                ComplicationDataSource.reloadComplications()
                ImageCache.trimUnaccessedEntries()
                state = drops.isEmpty ? .empty : .list
            }

        default:
            return
        }
    }

    nonisolated func session(_: WCSession, didReceiveMessageData messageData: Data) {
        guard let watchMessage = WatchMessage.parse(from: messageData) else {
            return
        }
        receivedInfo(message: watchMessage)
    }

    func getFullUpdate(session: WCSession) {
        if session.activationState == .activated {
            Task.detached { [weak self] in
                let reply = await session.sendWatchMessage(.updateRequest(full: true))
                self?.receivedInfo(message: reply)
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        Task {
            await getFullUpdate(session: session)
        }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext _: [String: Any]) {}
}
