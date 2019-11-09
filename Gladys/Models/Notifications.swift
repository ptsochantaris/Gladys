//
//  Notifications.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 11/02/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension Notification.Name {
	static let SaveComplete = Notification.Name("SaveComplete")
	static let ItemCollectionNeedsDisplay = Notification.Name("ItemCollectionNeedsDisplay")
	static let ExternalDataUpdated = Notification.Name("ExternalDataUpdated")
	static let ItemModified = Notification.Name("ItemModified")
    static let ItemsRemoved = Notification.Name("ItemsRemoved")
	static let LabelsUpdated = Notification.Name("LabelsUpdated")
	static let LabelSelectionChanged = Notification.Name("LabelSelectionChanged")
	static let DetailViewClosing = Notification.Name("DetailViewClosing")
	static let CloudManagerStatusChanged = Notification.Name("CloudManagerStatusChanged")
	static let ReachabilityChanged = Notification.Name("ReachabilityChanged")
	static let IngestComplete = Notification.Name("IngestComplete")
	static let AcceptStarting = Notification.Name("AcceptStarting")
	static let AcceptEnding = Notification.Name("AcceptEnding")
	static let ForegroundDisplayedItem = Notification.Name("ForegroundDisplayedItem")
	static let AlwaysOnTopChanged = Notification.Name("AlwaysOnTopChanged")
    static let NoteLastActionedUUID = Notification.Name("NoteLastActionedUUID")
    static let ForceLayoutRequested = Notification.Name("ForceLayoutRequested")
}

#if MAC
extension Notification.Name {
	static let IAPModeChanged = Notification.Name("IAPModeChanged")
}
#endif
