//
//  ExtensionDelegate.swift
//  GladysWatch Extension
//
//  Created by Paul Tsochantaris on 14/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import WatchKit
import WatchConnectivity

class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {

	static var currentUUID = ""

	private func extractDropList(from context: [String: Any]) -> [[String: Any]] {
		if
			let compressedData = context["dropList"] as? Data,
			let uncompressedData = compressedData.data(operation: .decompress),
			let itemInfo = NSKeyedUnarchiver.unarchiveObject(with: uncompressedData) as? [[String : Any]] {
			var count = 1
			let total = itemInfo.count
			return itemInfo.map { dict in
				var d = dict
				d["it"] = "\(count) of \(total)"
				count += 1
				return d
			}
		} else {
			return []
		}
	}

	private let updateQueue = DispatchQueue.init(label: "build.bru.Gladys.watch.updates", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem, target: nil)

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		updateQueue.async {
			self.updatePages(session.receivedApplicationContext)
		}
	}

	func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
		updateQueue.async {
			self.updatePages(applicationContext)
		}
	}

	private func updatePages(_ compressedList: [String: Any]) {
		let dropList = extractDropList(from: compressedList)
		if dropList.isEmpty {
			DispatchQueue.main.sync {
				WKInterfaceController.reloadRootPageControllers(withNames: ["StartupController"], contexts: nil, orientation: .vertical, pageIndex: 0)
			}
		} else {
			let names = [String](repeating: "ItemController", count: dropList.count)
			let currentUUID = ExtensionDelegate.currentUUID
			let currentPage = dropList.index { $0["u"] as? String == currentUUID } ?? 0
			let index = min(currentPage, names.count-1)
			DispatchQueue.main.sync {
				WKInterfaceController.reloadRootPageControllers(withNames: names, contexts: dropList, orientation: .vertical, pageIndex: index)
			}
		}
	}

    func applicationDidFinishLaunching() {
		let session = WCSession.default
		session.delegate = self
		session.activate()
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
