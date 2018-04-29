//
//  AppDelegate.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 28/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {



	func applicationDidFinishLaunching(_ aNotification: Notification) {
		if CloudManager.syncSwitchedOn {
			NSApplication.shared.registerForRemoteNotifications(matching: [.badge])
		}
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		// Insert code here to tear down your application
	}

	func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
		CloudManager.received(notificationInfo: userInfo)
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		NSApplication.shared.windows.first(where: { $0.contentViewController is ViewController })?.makeKeyAndOrderFront(self)
		return false
	}
}

