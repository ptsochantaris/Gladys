import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    @objc private func terminate() {
        log("Gladys launched, helper can now terminate")
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_: Notification) {
        if LauncherCommon.isMainAppRunning {
            log("Gladys already running, no need to start helper")
            NSApp.terminate(nil)
        } else {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(terminate), name: .KillHelper, object: LauncherCommon.mainAppId)
            LauncherCommon.launchMainApp()
        }
    }
}
