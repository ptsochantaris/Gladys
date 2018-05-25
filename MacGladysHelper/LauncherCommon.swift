//
//  LauncherCommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 25/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

extension Notification.Name {
	static let KillHelper = Notification.Name("KillHelper")
}

class LauncherCommon {

	static let helperAppId = "build.bru.MacGladysHelper"
	static var isHelperRunning: Bool {
		return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == helperAppId }
	}

	static let mainAppId = "build.bru.MacGladys"
	static var isMainAppRunning: Bool {
		return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == mainAppId }
	}

	static func killHelper() {
		if isHelperRunning {
			DistributedNotificationCenter.default().post(name: .KillHelper, object: mainAppId)
		}
	}

	static func launchMainApp() {
		if isMainAppRunning { return }
		let path = "/" + Bundle.main.bundlePath.split(separator: "/").dropLast(3).joined(separator: "/") + "/MacOS/MacGladys"
		NSWorkspace.shared.launchApplication(path)
	}
}
