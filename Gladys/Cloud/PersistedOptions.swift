//
//  PersistedOptions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 15/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation

class PersistedOptions {

	static var defaults: UserDefaults = { return UserDefaults(suiteName: "group.build.bru.Gladys")! }()

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
}
