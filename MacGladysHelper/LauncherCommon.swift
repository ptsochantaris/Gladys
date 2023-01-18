import Cocoa
import GladysCommon

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
        var finalPathComponents = [String.SubSequence]()
        for component in Bundle.main.bundlePath.split(separator: "/") {
            finalPathComponents.append(component)
            if component.hasSuffix(".app") {
                break
            }
        }
        let path = "/" + finalPathComponents.joined(separator: "/")
        let config = NSWorkspace.OpenConfiguration()
        log("Will launch Gladys at \(path)")
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config) { _, error in
            if let error {
                log("Error launching Gladys: \(error.localizedDescription)")
            }
        }
    }
}
