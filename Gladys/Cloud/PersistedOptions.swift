//
//  PersistedOptions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 15/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import Foundation

enum DefaultTapAction: Int {
	case infoPanel = 0, preview, open, copy, none
}

final class PersistedOptions {

	static let defaults = UserDefaults(suiteName: groupName)!

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
    
    static var extensionRequestedSync: Bool {
        get {
            return defaults.bool(forKey: "extensionRequestedSync")
        }
        set {
            defaults.set(newValue, forKey: "extensionRequestedSync")
        }
    }

    static var autoGenerateLabelsFromText: Bool {
        get {
            return defaults.bool(forKey: "autoGenerateLabelsFromText")
        }
        set {
            defaults.set(newValue, forKey: "autoGenerateLabelsFromText")
        }
    }

    static var autoGenerateLabelsFromImage: Bool {
        get {
            return defaults.bool(forKey: "autoGenerateLabelsFromImage")
        }
        set {
            defaults.set(newValue, forKey: "autoGenerateLabelsFromImage")
        }
    }
    
    static var transcribeSpeechFromMedia: Bool {
        get {
            return defaults.bool(forKey: "transcribeSpeechFromMedia")
        }
        set {
            defaults.set(newValue, forKey: "transcribeSpeechFromMedia")
        }
    }
    
    static var includeUrlImagesInMlLogic: Bool {
        get {
            return defaults.bool(forKey: "includeUrlImagesInMlLogic")
        }
        set {
            defaults.set(newValue, forKey: "includeUrlImagesInMlLogic")
        }
    }

    static var autoGenerateTextFromImage: Bool {
        get {
            return defaults.bool(forKey: "autoGenerateTextFromImage")
        }
        set {
            defaults.set(newValue, forKey: "autoGenerateTextFromImage")
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
    
    static var mirrorFilesToDocuments: Bool {
        get {
            return defaults.bool(forKey: "mirrorFilesToDocuments")
        }
        set {
            defaults.set(newValue, forKey: "mirrorFilesToDocuments")
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

	static var exclusiveMultipleLabels: Bool {
		get {
			return defaults.bool(forKey: "exclusiveMultipleLabels")
		}
		set {
			defaults.set(newValue, forKey: "exclusiveMultipleLabels")
		}
	}

	static var autoArchiveUrlComponents: Bool {
		get {
			return defaults.bool(forKey: "autoArchiveUrlComponents")
		}
		set {
			defaults.set(newValue, forKey: "autoArchiveUrlComponents")
		}
	}

	static var actionOnTap: DefaultTapAction {
		get {
			let value = defaults.integer(forKey: "actionOnTap")
			return DefaultTapAction(rawValue: value) ?? .infoPanel
		}
		set {
			defaults.set(newValue.rawValue, forKey: "actionOnTap")
		}
	}

    static var actionOnTouchbar: DefaultTapAction {
        get {
            let value = defaults.integer(forKey: "actionOnTouchbar")
            return DefaultTapAction(rawValue: value) ?? .infoPanel
        }
        set {
            defaults.set(newValue.rawValue, forKey: "actionOnTouchbar")
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

	static var inclusiveSearchTerms: Bool {
		get {
			return defaults.bool(forKey: "inclusiveSearchTerms")
		}
		set {
			defaults.set(newValue, forKey: "inclusiveSearchTerms")
		}
	}

	static var lastRanVersion: String? {
        get {
            return UserDefaults.standard.string(forKey: "LastRanVersion")
        }
		set {
			let d = UserDefaults.standard
			if let newValue = newValue {
				d.set(newValue, forKey: "LastRanVersion")
			} else {
				d.removeObject(forKey: "LastRanVersion")
			}
		}
	}
    
    static var automaticallyDetectAndConvertWebLinks: Bool {
        get {
            return defaults.bool(forKey: "AutomaticallyConvertWebLinks")
        }
        set {
            defaults.set(newValue, forKey: "AutomaticallyConvertWebLinks")
        }
    }
    
    static var readAndStoreFinderTagsAsLabels: Bool {
        get {
            return defaults.bool(forKey: "ReadAndStoreFinderTagsAsLabels")
        }
        set {
            defaults.set(newValue, forKey: "ReadAndStoreFinderTagsAsLabels")
        }
    }
    
    static var blockGladysUrlRequests: Bool {
        get {
            return defaults.bool(forKey: "BlockGladysUrlRequests")
        }
        set {
            defaults.set(newValue, forKey: "BlockGladysUrlRequests")
        }
    }
    
    static var badgeIconWithItemCount: Bool {
        get {
            return defaults.bool(forKey: "badgeIconWithItemCount")
        }
        set {
            defaults.set(newValue, forKey: "badgeIconWithItemCount")
        }
    }
    
    static var migratedSubscriptions7: Bool {
        get {
            return defaults.bool(forKey: "migratedSubscriptions7")
        }
        set {
            defaults.set(newValue, forKey: "migratedSubscriptions7")
        }
    }
    
    static var requestInlineDrops: Bool {
        get {
            return defaults.bool(forKey: "requestInlineDrops")
        }
        set {
            defaults.set(newValue, forKey: "requestInlineDrops")
        }
    }
}
