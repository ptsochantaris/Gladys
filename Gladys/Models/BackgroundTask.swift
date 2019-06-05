//
//  BackgroundTask.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 05/06/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class BackgroundTask {

	private static var bgTask = UIBackgroundTaskIdentifier.invalid

	private static func end() {
		if bgTask == .invalid { return }
		log("BG Task done")
		UIApplication.shared.endBackgroundTask(bgTask)
		bgTask = .invalid
	}

	private static var globalBackgroundCount = 0

	private static let endTimer = PopTimer(timeInterval: 3) {
		end()
	}

	static func registerForBackground() {
		DispatchQueue.main.async {
			if endTimer.isRunning {
				endTimer.abort()
			}
			if globalBackgroundCount == 0 && bgTask == .invalid {
				log("BG Task starting")
				bgTask = UIApplication.shared.beginBackgroundTask {
					end()
				}
			}
			globalBackgroundCount += 1
		}
	}

	static func unregisterForBackground() {
		DispatchQueue.main.async {
			globalBackgroundCount -= 1
			if globalBackgroundCount == 0 && bgTask != .invalid {
				endTimer.push()
			}
		}
	}
}
