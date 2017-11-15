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

	private var dropList = [[String: Any]]()

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		DispatchQueue.main.async {
			self.dropList = session.receivedApplicationContext["dropList"] as? [[String: Any]] ?? []
			self.updatePages()
		}
	}

	func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
		DispatchQueue.main.async {
			self.dropList = applicationContext["dropList"] as? [[String: Any]] ?? []
			self.updatePages()
		}
	}

	private func updatePages() {
		if dropList.count > 0 {
			var names = [String]()
			for _ in 0 ..< dropList.count {
				names.append("ItemController")
			}
			WKInterfaceController.reloadRootPageControllers(withNames: names,
															contexts: dropList,
															orientation: .vertical,
															pageIndex: 0)
		} else {
			WKInterfaceController.reloadRootPageControllers(withNames: ["StartupController"],
															contexts: nil,
															orientation: .vertical,
															pageIndex: 0)
		}
	}

    func applicationDidFinishLaunching() {
		let session = WCSession.default
		session.delegate = self
		session.activate()
    }

    func applicationDidBecomeActive() {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillResignActive() {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, etc.
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // Sent when the system needs to launch the application in the background to process tasks. Tasks arrive in a set, so loop through and process each one.
        for task in backgroundTasks {
            // Use a switch statement to check the task type
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                // Be sure to complete the background task once you’re done.
                backgroundTask.setTaskCompletedWithSnapshot(false)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                // Snapshot tasks have a unique completion call, make sure to set your expiration date
                snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                // Be sure to complete the connectivity task once you’re done.
                connectivityTask.setTaskCompletedWithSnapshot(false)
            case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
                // Be sure to complete the URL session task once you’re done.
                urlSessionTask.setTaskCompletedWithSnapshot(false)
            default:
                // make sure to complete unhandled task types
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

}
