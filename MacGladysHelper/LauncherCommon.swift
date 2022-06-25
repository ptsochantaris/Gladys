import Cocoa

extension Notification.Name {
    static let KillHelper = Notification.Name("KillHelper")
}

enum LauncherCommon {
    static let helperAppId = "build.bru.MacGladys.Helper"
    static var isHelperRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == helperAppId }
    }

    static let mainAppId = "build.bru.MacGladys"
    static var isMainAppRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == mainAppId }
    }

    static func killHelper() {
        if isHelperRunning {
            DistributedNotificationCenter.default().post(name: .KillHelper, object: mainAppId)
        }
    }

    static func launchMainApp() {
        if isMainAppRunning { return }
        let path = "/" + Bundle.main.bundlePath.split(separator: "/").dropLast(3).joined(separator: "/") + "/MacOS/Gladys"
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config)
    }
}
