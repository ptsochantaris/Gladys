//
//  Notifications.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 11/02/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

struct HighlightRequest {
    let uuid: String
    let open: Bool
    let preview: Bool
    let focusOnChildUuid: String?
    
    init(uuid: String, open: Bool = false, preview: Bool = false, focusOnChildUuid: String? = nil) {
        self.uuid = uuid
        self.open = open
        self.preview = preview
        self.focusOnChildUuid = focusOnChildUuid
    }
}

struct PasteRequest {
    let providers: [NSItemProvider]
    let overrides: ImportOverrides?
    let skipVisibleErrors: Bool
}

extension Notification.Name {
	static let SaveComplete = Notification.Name("SaveComplete")
	static let ItemCollectionNeedsDisplay = Notification.Name("ItemCollectionNeedsDisplay")
	static let ExternalDataUpdated = Notification.Name("ExternalDataUpdated")
    static let ItemsCreated = Notification.Name("ItemsCreated")
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
    static let HighlightItemRequested = Notification.Name("HighlightItemRequested")
}

#if MAC
extension Notification.Name {
	static let IAPModeChanged = Notification.Name("IAPModeChanged")
}
#endif
