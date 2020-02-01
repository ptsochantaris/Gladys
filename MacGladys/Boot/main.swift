//
//  main.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 09/09/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!) where app != NSRunningApplication.current {
    app.activate(options: [.activateIgnoringOtherApps])
    exit(0)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
