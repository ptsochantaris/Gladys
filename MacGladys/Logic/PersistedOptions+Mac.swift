import Cocoa
import ServiceManagement

extension PersistedOptions {

	static var hotkeyCmd: Bool {
		get {
			return defaults.bool(forKey: "hotkeyCmd")
		}
		set {
			defaults.set(newValue, forKey: "hotkeyCmd")
		}
	}
	static var hotkeyOption: Bool {
		get {
			return defaults.bool(forKey: "hotkeyOption")
		}
		set {
			defaults.set(newValue, forKey: "hotkeyOption")
		}
	}
	static var hotkeyShift: Bool {
		get {
			return defaults.bool(forKey: "hotkeyShift")
		}
		set {
			defaults.set(newValue, forKey: "hotkeyShift")
		}
	}
	static var hotkeyCtrl: Bool {
		get {
			return defaults.bool(forKey: "hotkeyCtrl")
		}
		set {
			defaults.set(newValue, forKey: "hotkeyCtrl")
		}
	}
	static var hotkeyChar: Int {
		get {

			return defaults.integer(forKey: "hotkeyChar")
		}
		set {
			defaults.set(newValue, forKey: "hotkeyChar")
		}
	}

	static var unconfirmedDeletes: Bool {
		get {
			return defaults.bool(forKey: "unconfirmedDeletes")
		}
		set {
			defaults.set(newValue, forKey: "unconfirmedDeletes")
		}
	}

	static var hideMainWindowAtStartup: Bool {
		get {
			return defaults.bool(forKey: "hideMainWindowAtStartup")
		}
		set {
			defaults.set(newValue, forKey: "hideMainWindowAtStartup")
		}
	}

	static var launchAtLogin: Bool {
		get {
			return defaults.bool(forKey: "launchAtLogin")
		}
		set {
			defaults.set(newValue, forKey: "launchAtLogin")
			SMLoginItemSetEnabled(LauncherCommon.helperAppId as CFString, newValue)
		}
	}

	static var defaultsVersion: Int {
		get {
			return defaults.integer(forKey: "defaultsVersion")
		}
		set {
			defaults.set(newValue, forKey: "defaultsVersion")
		}
	}

	static var menubarIconMode: Bool {
		get {
			return defaults.bool(forKey: "menubarIconMode")
		}
		set {
			defaults.set(newValue, forKey: "menubarIconMode")
		}
	}

	static var alwaysOnTop: Bool {
		get {
			return defaults.bool(forKey: "alwaysOnTop")
		}
		set {
			defaults.set(newValue, forKey: "alwaysOnTop")
		}
	}

	static var hideTitlebar: Bool {
		get {
			return defaults.bool(forKey: "hideTitlebar")
		}
		set {
			defaults.set(newValue, forKey: "hideTitlebar")
		}
	}
    
    static var autoShowWhenDragging: Bool {
        get {
            return defaults.bool(forKey: "autoShowWhenDragging")
        }
        set {
            defaults.set(newValue, forKey: "autoShowWhenDragging")
        }
    }

    static var autoShowFromEdge: Int {
        get {
            return defaults.integer(forKey: "autoShowFromEdge")
        }
        set {
            defaults.set(newValue, forKey: "autoShowFromEdge")
        }
    }
}
