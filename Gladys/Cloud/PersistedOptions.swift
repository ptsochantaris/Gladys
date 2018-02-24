//
//  PersistedOptions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 15/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation

class PersistedOptions {

	static var defaults = UserDefaults(suiteName: "group.build.bru.Gladys")!

	static func migrateBrokenDefaults() { // keep this around for a while
		if let brokenDefaults = UserDefaults(suiteName: "group.buildefaults.bru.Gladys") {
			var changes = false
			for key in ["separateItemPreference", "forceTwoColumnPreference", "lastiCloudAccount", "lastSyncCompletion", "zoneChangeMayNotReflectSavedChanges", "syncSwitchedOn", "onlySyncOverWiFi", "zoneChangeToken", "uuidSequence"] {
				if let o = brokenDefaults.object(forKey: key) {
					defaults.set(o, forKey: key)
					brokenDefaults.removeObject(forKey: key)
					changes = true
				}
			}
			if changes {
				brokenDefaults.synchronize()
				defaults.synchronize()
			}
		}
	}

	static var darkMode: Bool {
		get {
			return defaults.bool(forKey: "darkMode")
		}
		set {
			defaults.set(newValue, forKey: "darkMode")
			defaults.synchronize()
		}
	}

	static var fullScreenPreviews: Bool {
		get {
			return defaults.bool(forKey: "fullScreenPreviews")
		}
		set {
			defaults.set(newValue, forKey: "fullScreenPreviews")
			defaults.synchronize()
		}
	}

	static var showCopyMoveSwitchSelector: Bool {
		get {
			return defaults.bool(forKey: "showCopyMoveSwitchSelector")
		}
		set {
			defaults.set(newValue, forKey: "showCopyMoveSwitchSelector")
			defaults.synchronize()
		}
	}

	static var displayNotesInMainView: Bool {
		get {
			return defaults.bool(forKey: "displayNotesInMainView")
		}
		set {
			defaults.set(newValue, forKey: "displayNotesInMainView")
			defaults.synchronize()
		}
	}

	static var watchComplicationText: String {
		get {
			return defaults.string(forKey: "watchComplicationText") ?? ""
		}
		set {
			defaults.set(newValue, forKey: "watchComplicationText")
			defaults.synchronize()
		}
	}

	static var removeItemsWhenDraggedOut: Bool {
		get {
			return defaults.bool(forKey: "removeItemsWhenDraggedOut")
		}
		set {
			defaults.set(newValue, forKey: "removeItemsWhenDraggedOut")
			defaults.synchronize()
		}
	}

	static var dontAutoLabelNewItems: Bool {
		get {
			return defaults.bool(forKey: "dontAutoLabelNewItems")
		}
		set {
			defaults.set(newValue, forKey: "dontAutoLabelNewItems")
			defaults.synchronize()
		}
	}

	static var exportOnlyVisibleItems: Bool {
		get {
			return defaults.bool(forKey: "exportOnlyVisibleItems")
		}
		set {
			defaults.set(newValue, forKey: "exportOnlyVisibleItems")
			defaults.synchronize()
		}
	}

	static var separateItemPreference: Bool {
		get {
			return defaults.bool(forKey: "separateItemPreference")
		}
		set {
			defaults.set(newValue, forKey: "separateItemPreference")
			defaults.synchronize()
		}
	}

	static var forceTwoColumnPreference: Bool {
		get {
			return defaults.bool(forKey: "forceTwoColumnPreference")
		}
		set {
			defaults.set(newValue, forKey: "forceTwoColumnPreference")
			defaults.synchronize()
		}
	}

	static var lastSelectedPreferencesTab: Int {
		get {
			return defaults.integer(forKey: "lastSelectedPreferencesTab")
		}
		set {
			defaults.set(newValue, forKey: "lastSelectedPreferencesTab")
			defaults.synchronize()
		}
	}
}
