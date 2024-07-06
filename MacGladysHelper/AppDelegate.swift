import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @objc private func terminate() {
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_: Notification) {
        if LauncherCommon.isMainAppRunning {
            NSApp.terminate(nil)
        } else {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(terminate), name: .KillHelper, object: LauncherCommon.mainAppId)
            LauncherCommon.launchMainApp()
        }
    }
}
