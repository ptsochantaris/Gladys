import Cocoa
import ServiceManagement

extension PersistedOptions {

	static var hotkeyCmd: Bool {
		get {
			return defaults.bool(forKey: "hotkeyCmd")
		}
		set {
			defaults.set(newValue, forKey: "hotkeyCmd")
			defaults.synchronize()
		}
	}
	static var hotkeyOption: Bool {
		get {
			return defaults.bool(forKey: "hotkeyOption")
		}
		set {
			defaults.set(newValue, forKey: "hotkeyOption")
			defaults.synchronize()
		}
	}
	static var hotkeyShift: Bool {
		get {
			return defaults.bool(forKey: "hotkeyShift")
		}
		set {
			defaults.set(newValue, forKey: "hotkeyShift")
			defaults.synchronize()
		}
	}
	static var hotkeyCtrl: Bool {
		get {
			return defaults.bool(forKey: "hotkeyCtrl")
		}
		set {
			defaults.set(newValue, forKey: "hotkeyCtrl")
			defaults.synchronize()
		}
	}
	static var hotkeyChar: Int {
		get {

			return defaults.integer(forKey: "hotkeyChar")
		}
		set {
			defaults.set(newValue, forKey: "hotkeyChar")
			defaults.synchronize()
		}
	}

	static var unconfirmedDeletes: Bool {
		get {
			return defaults.bool(forKey: "unconfirmedDeletes")
		}
		set {
			defaults.set(newValue, forKey: "unconfirmedDeletes")
			defaults.synchronize()
		}
	}

	static var hideMainWindowAtStartup: Bool {
		get {
			return defaults.bool(forKey: "hideMainWindowAtStartup")
		}
		set {
			defaults.set(newValue, forKey: "hideMainWindowAtStartup")
			defaults.synchronize()
		}
	}

	static var launchAtLogin: Bool {
		get {
			return defaults.bool(forKey: "launchAtLogin")
		}
		set {
			defaults.set(newValue, forKey: "launchAtLogin")
			defaults.synchronize()
			SMLoginItemSetEnabled(LauncherCommon.helperAppId as CFString, newValue)
		}
	}

	static var menubarIconMode: Bool {
		get {
			return defaults.bool(forKey: "menubarIconMode")
		}
		set {
			defaults.set(newValue, forKey: "menubarIconMode")
			defaults.synchronize()
		}
	}

	static var translucentMode: Bool {
		get {
			return defaults.bool(forKey: "translucentMode")
		}
		set {
			defaults.set(newValue, forKey: "translucentMode")
			defaults.synchronize()
		}
	}

	static var alwaysOnTop: Bool {
		get {
			return defaults.bool(forKey: "alwaysOnTop")
		}
		set {
			defaults.set(newValue, forKey: "alwaysOnTop")
			defaults.synchronize()
		}
	}
}
