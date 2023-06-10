import AppKit

for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!) where app != NSRunningApplication.current {
    app.activate(options: [.activateIgnoringOtherApps])
    exit(0)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
