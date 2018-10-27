//
//  PersistedOptions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 15/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation

class PersistedOptions {

	static let defaults = UserDefaults(suiteName: groupName)!

	static func migrateBrokenDefaults() { // keep this around for a while
		if let brokenDefaults = UserDefaults(suiteName: "group.buildefaults.bru.Gladys") {
			for key in ["separateItemPreference", "forceTwoColumnPreference", "lastiCloudAccount", "lastSyncCompletion", "zoneChangeMayNotReflectSavedChanges", "syncSwitchedOn", "onlySyncOverWiFi", "zoneChangeToken", "uuidSequence"] {
				if let o = brokenDefaults.object(forKey: key) {
					defaults.set(o, forKey: key)
					brokenDefaults.removeObject(forKey: key)
				}
			}
		}
	}

	private static var darkModeCache: Bool?
	static var darkMode: Bool {
		get {
			if let c = darkModeCache {
				return c
			}
			darkModeCache = defaults.bool(forKey: "darkMode")
			return darkModeCache!
		}
		set {
			darkModeCache = newValue
			defaults.set(newValue, forKey: "darkMode")
		}
	}

	private static var allowMergeOfTypeItemsCache: Bool?
	static var allowMergeOfTypeItems: Bool {
		get {
			if let c = allowMergeOfTypeItemsCache {
				return c
			}
			allowMergeOfTypeItemsCache = defaults.bool(forKey: "allowMergeOfTypeItems")
			return allowMergeOfTypeItemsCache!
		}
		set {
			allowMergeOfTypeItemsCache = newValue
			defaults.set(newValue, forKey: "allowMergeOfTypeItems")
		}
	}

	private static var wideModeCache: Bool?
	static var wideMode: Bool {
		get {
			if let c = wideModeCache {
				return c
			}
			wideModeCache = defaults.bool(forKey: "wideMode")
			return wideModeCache!
		}
		set {
			wideModeCache = newValue
			defaults.set(newValue, forKey: "wideMode")
		}
	}

	static var setLabelsWhenActioning: Bool {
		get {
			return defaults.bool(forKey: "setLabelsWhenActioning")
		}
		set {
			defaults.set(newValue, forKey: "setLabelsWhenActioning")
		}
	}

	static var fullScreenPreviews: Bool {
		get {
			return defaults.bool(forKey: "fullScreenPreviews")
		}
		set {
			defaults.set(newValue, forKey: "fullScreenPreviews")
		}
	}

	static var showCopyMoveSwitchSelector: Bool {
		get {
			return defaults.bool(forKey: "showCopyMoveSwitchSelector")
		}
		set {
			defaults.set(newValue, forKey: "showCopyMoveSwitchSelector")
		}
	}

	static var displayNotesInMainView: Bool {
		get {
			return defaults.bool(forKey: "displayNotesInMainView")
		}
		set {
			defaults.set(newValue, forKey: "displayNotesInMainView")
		}
	}

	static var displayLabelsInMainView: Bool {
		get {
			return defaults.bool(forKey: "displayLabelsInMainView")
		}
		set {
			defaults.set(newValue, forKey: "displayLabelsInMainView")
		}
	}

	static var removeItemsWhenDraggedOut: Bool {
		get {
			return defaults.bool(forKey: "removeItemsWhenDraggedOut")
		}
		set {
			defaults.set(newValue, forKey: "removeItemsWhenDraggedOut")
		}
	}

	static var dontAutoLabelNewItems: Bool {
		get {
			return defaults.bool(forKey: "dontAutoLabelNewItems")
		}
		set {
			defaults.set(newValue, forKey: "dontAutoLabelNewItems")
		}
	}

	static var exportOnlyVisibleItems: Bool {
		get {
			return defaults.bool(forKey: "exportOnlyVisibleItems")
		}
		set {
			defaults.set(newValue, forKey: "exportOnlyVisibleItems")
		}
	}

	static var separateItemPreference: Bool {
		get {
			return defaults.bool(forKey: "separateItemPreference")
		}
		set {
			defaults.set(newValue, forKey: "separateItemPreference")
		}
	}

	static var forceTwoColumnPreference: Bool {
		get {
			return defaults.bool(forKey: "forceTwoColumnPreference")
		}
		set {
			defaults.set(newValue, forKey: "forceTwoColumnPreference")
		}
	}

	static var pasteShortcutAutoDonated: Bool {
		get {
			return defaults.bool(forKey: "pasteShortcutAutoDonated")
		}
		set {
			defaults.set(newValue, forKey: "pasteShortcutAutoDonated")
		}
	}

	static var lastSelectedPreferencesTab: Int {
		get {
			return defaults.integer(forKey: "lastSelectedPreferencesTab")
		}
		set {
			defaults.set(newValue, forKey: "lastSelectedPreferencesTab")
		}
	}

	static var lastPushToken: Data? {
		get {
			return defaults.data(forKey: "lastPushToken")
		}
		set {
			if let n = newValue {
				defaults.set(n, forKey: "lastPushToken")
			} else {
				defaults.set(Data(), forKey: "lastPushToken")
			}
		}
	}
}
