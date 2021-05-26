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
    
    static var clipboardSnooping: Bool {
        get {
            return defaults.bool(forKey: "clipboardSnooping")
        }
        set {
            defaults.set(newValue, forKey: "clipboardSnooping")
        }
    }

    static var clipboardSnoopingAll: Bool {
        get {
            return defaults.bool(forKey: "clipboardSnoopingAll")
        }
        set {
            defaults.set(newValue, forKey: "clipboardSnoopingAll")
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
    
    private static var _autoShowWhenDragging: Bool?
    static var autoShowWhenDragging: Bool {
        get {
            if let _autoShowWhenDragging = _autoShowWhenDragging {
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

    private static var _autoShowFromEdge: Int?
    static var autoShowFromEdge: Int {
        get {
            if let _autoShowFromEdge = _autoShowFromEdge {
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
            return defaults.integer(forKey: "autoHideAfter")
        }
        set {
            defaults.set(newValue, forKey: "autoHideAfter")
        }
    }
}
