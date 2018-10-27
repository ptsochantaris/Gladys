//
//  CloudManager+Storage.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 27/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CloudKit
#if MAINAPP
	import UIKit
#endif

extension CloudManager {

	static var shareActionIsActioningIds: [String] {
		get {
			return PersistedOptions.defaults.object(forKey: "shareActionIsActioningIds") as? [String] ?? []
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "shareActionIsActioningIds")
		}
	}

	static var onlySyncOverWiFi: Bool {
		get {
			return PersistedOptions.defaults.bool(forKey: "onlySyncOverWiFi")
		}

		set {
			PersistedOptions.defaults.set(newValue, forKey: "onlySyncOverWiFi")
		}
	}
}
