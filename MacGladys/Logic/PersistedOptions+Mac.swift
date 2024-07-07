import AppKit
import GladysCommon
import ServiceManagement

extension PersistedOptions {
    static var hotkeyCmd: Bool {
        get {
            defaults.bool(forKey: "hotkeyCmd")
        }
        set {
            defaults.set(newValue, forKey: "hotkeyCmd")
        }
    }

    static var hotkeyOption: Bool {
        get {
            defaults.bool(forKey: "hotkeyOption")
        }
        set {
            defaults.set(newValue, forKey: "hotkeyOption")
        }
    }

    static var hotkeyShift: Bool {
        get {
            defaults.bool(forKey: "hotkeyShift")
        }
        set {
            defaults.set(newValue, forKey: "hotkeyShift")
        }
    }

    static var hotkeyCtrl: Bool {
        get {
            defaults.bool(forKey: "hotkeyCtrl")
        }
        set {
            defaults.set(newValue, forKey: "hotkeyCtrl")
        }
    }

    static var hotkeyChar: Int {
        get {
            defaults.integer(forKey: "hotkeyChar")
        }
        set {
            defaults.set(newValue, forKey: "hotkeyChar")
        }
    }

    static var unconfirmedDeletes: Bool {
        get {
            defaults.bool(forKey: "unconfirmedDeletes")
        }
        set {
            defaults.set(newValue, forKey: "unconfirmedDeletes")
        }
    }

    static var hideMainWindowAtStartup: Bool {
        get {
            defaults.bool(forKey: "hideMainWindowAtStartup")
        }
        set {
            defaults.set(newValue, forKey: "hideMainWindowAtStartup")
        }
    }

    private static var loginItem: SMAppService {
        SMAppService.loginItem(identifier: LauncherCommon.helperAppId)
    }

    static var launchAtLogin: Bool {
        get {
            switch loginItem.status {
            case .notFound, .notRegistered: false
            case .enabled, .requiresApproval: true
            @unknown default: false
            }
        }
        set {
            try? newValue ? loginItem.register() : loginItem.unregister()
        }
    }

    static var defaultsVersion: Int {
        get {
            defaults.integer(forKey: "defaultsVersion")
        }
        set {
            defaults.set(newValue, forKey: "defaultsVersion")
        }
    }

    static var menubarIconMode: Bool {
        get {
            defaults.bool(forKey: "menubarIconMode")
        }
        set {
            defaults.set(newValue, forKey: "menubarIconMode")
        }
    }

    static var clipboardSnooping: Bool {
        get {
            defaults.bool(forKey: "clipboardSnooping")
        }
        set {
            defaults.set(newValue, forKey: "clipboardSnooping")
        }
    }

    static var clipboardSnoopingAll: Bool {
        get {
            defaults.bool(forKey: "clipboardSnoopingAll")
        }
        set {
            defaults.set(newValue, forKey: "clipboardSnoopingAll")
        }
    }

    static var clipboardSnoopingLabel: String {
        get {
            defaults.string(forKey: "clipboardSnoopingLabel") ?? ""
        }
        set {
            defaults.set(newValue, forKey: "clipboardSnoopingLabel")
        }
    }

    static var alwaysOnTop: Bool {
        get {
            defaults.bool(forKey: "alwaysOnTop")
        }
        set {
            defaults.set(newValue, forKey: "alwaysOnTop")
        }
    }

    static var hideTitlebar: Bool {
        get {
            defaults.bool(forKey: "hideTitlebar")
        }
        set {
            defaults.set(newValue, forKey: "hideTitlebar")
        }
    }

    @MainActor
    private static var _autoShowWhenDragging: Bool?

    @MainActor
    static var autoShowWhenDragging: Bool {
        get {
            if let _autoShowWhenDragging {
                return _autoShowWhenDragging
            }
            _autoShowWhenDragging = defaults.bool(forKey: "autoShowWhenDragging")
            return _autoShowWhenDragging!
        }
        set {
            _autoShowWhenDragging = newValue
            defaults.set(newValue, forKey: "autoShowWhenDragging")
        }
    }

    @MainActor
    private static var _autoShowFromEdge: Int?

    @MainActor
    static var autoShowFromEdge: Int {
        get {
            if let _autoShowFromEdge {
                return _autoShowFromEdge
            }
            _autoShowFromEdge = defaults.integer(forKey: "autoShowFromEdge")
            return _autoShowFromEdge!
        }
        set {
            _autoShowFromEdge = newValue
            defaults.set(newValue, forKey: "autoShowFromEdge")
            if newValue == 0 {
                NSApp.orderedWindows.compactMap { $0.contentViewController as? ViewController }.forEach {
                    guard let w = $0.view.window else { return }
                    $0.showWindow(window: w)
                }
            } else {
                NSApp.orderedWindows.compactMap { $0.contentViewController as? ViewController }.forEach {
                    guard let w = $0.view.window else { return }
                    $0.hideWindowBecauseOfMouse(window: w)
                }
            }
        }
    }

    static var autoHideAfter: Int {
        get {
            defaults.integer(forKey: "autoHideAfter")
        }
        set {
            defaults.set(newValue, forKey: "autoHideAfter")
        }
    }
}
