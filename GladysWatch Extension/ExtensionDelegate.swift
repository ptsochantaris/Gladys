//
//  ExtensionDelegate.swift
//  GladysWatch Extension
//
//  Created by Paul Tsochantaris on 14/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import ClockKit
import GladysFramework
import WatchConnectivity
import WatchKit

final class ImageCache {
    private static let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!

    private static let accessKeys = Set([URLResourceKey.contentAccessDateKey])

    static func setImageData(_ data: Data, for key: String) {
        let imageUrl = cacheDir.appendingPathComponent(key)
        do {
            try data.write(to: imageUrl)
        } catch {
            print("Error writing data to: \(error.localizedDescription)")
        }
    }

    static func imageData(for key: String) -> Data? {
        var imageUrl = cacheDir.appendingPathComponent(key)
        if FileManager.default.fileExists(atPath: imageUrl.path) {
            var v = URLResourceValues()
            let now = Date()
            v.contentModificationDate = now
            v.contentAccessDate = now
            try? imageUrl.setResourceValues(v)
            return try? Data(contentsOf: imageUrl, options: .mappedIfSafe)
        }
        return nil
    }

    static func trimUnaccessedEntries() {
        if let cachedFiles = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]) {
            let now = Date()
            let fm = FileManager.default
            for file in cachedFiles {
                if let accessDate = (try? file.resourceValues(forKeys: accessKeys))?.contentAccessDate {
                    if now.timeIntervalSince(accessDate) > (3600 * 24 * 7) {
                        try? fm.removeItem(at: file)
                    }
                }
            }
        }
    }
}

final class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {
    static var currentUUID = ""
    static var reportedCount = 0

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
        DispatchQueue.main.sync {
            ExtensionDelegate.reportedCount = reportedCount
            reloadComplications()
        }
        if dropList.isEmpty {
            DispatchQueue.main.sync {
                WKInterfaceController.reloadRootPageControllers(withNames: ["EmptyController"], contexts: nil, orientation: .vertical, pageIndex: 0)
            }
        } else {
            let names = [String](repeating: "ItemController", count: dropList.count)
            let currentUUID = ExtensionDelegate.currentUUID
            let currentPage = dropList.firstIndex { $0["u"] as? String == currentUUID } ?? 0
            let index = min(currentPage, names.count - 1)
            DispatchQueue.main.sync {
                WKInterfaceController.reloadRootPageControllers(withNames: names, contexts: dropList, orientation: .vertical, pageIndex: index)
            }
        }
        DispatchQueue.main.sync {
            ImageCache.trimUnaccessedEntries()
        }
    }

    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receivedInfo(userInfo)
    }

    private func getFullUpdate(session: WCSession) {
        if session.activationState == .activated {
            session.sendMessage(["update": "full"], replyHandler: { [weak self] info in
                self?.receivedInfo(info)
            }, errorHandler: nil)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        getFullUpdate(session: session)
    }

    func session(_: WCSession, didReceiveApplicationContext _: [String: Any]) {}

    private func reloadComplications() {
        let s = CLKComplicationServer.sharedInstance()
        s.activeComplications?.forEach {
            s.reloadTimeline(for: $0)
        }
    }

    func applicationDidFinishLaunching() {
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func applicationWillEnterForeground() {
        let session = WCSession.default
        getFullUpdate(session: session)
    }

    func applicationDidEnterBackground() {
        reloadComplications()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                backgroundTask.setTaskCompletedWithSnapshot(false)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                snapshotTask.setTaskCompleted(restoredDefaultState: false, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                connectivityTask.setTaskCompletedWithSnapshot(false)
            case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
                urlSessionTask.setTaskCompletedWithSnapshot(false)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
