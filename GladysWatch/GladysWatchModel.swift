import GladysCommon
import WatchConnectivity
import Minions

final class GladysWatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var reportedCount = 0
    @Published var dropList = [Drop]()

    static let shared = GladysWatchModel()

    enum State {
        case loading, empty, list
    }

    var state = State.loading

    private func extractDropList(from context: [String: Any]) -> ([[String: Any]], Int) {
        if
            let reportedCount = context["total"] as? Int,
            let compressedData = context["dropList"] as? Data,
            let uncompressedData = compressedData.data(operation: .decompress),
            let itemInfo = SafeArchiving.unarchive(uncompressedData) as? [[String: Any]] {
            var count = 1
            let list = itemInfo.map { dict -> [String: Any] in
                var d = dict
                d["it"] = "\(count) of \(reportedCount)"
                count += 1
                return d
            }
            return (list, reportedCount)
        } else {
            return ([], 0)
        }
    }

    private func receivedInfo(_ info: [String: Any]) {
        let (dropList, reportedCount) = extractDropList(from: info)
        Task { @MainActor in
            self.reportedCount = reportedCount
            self.dropList = dropList.compactMap { Drop(json: $0) }
            ComplicationDataSource.reloadComplications()
            ImageCache.trimUnaccessedEntries()
            state = dropList.isEmpty ? .empty : .list
        }
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receivedInfo(userInfo)
    }

    func getFullUpdate(session: WCSession) {
        if session.activationState == .activated {
            session.sendMessage(["update": "full"], replyHandler: #weakSelf { info in
                receivedInfo(info)
            })
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        getFullUpdate(session: session)
    }

    func session(_: WCSession, didReceiveApplicationContext _: [String: Any]) {}
}
