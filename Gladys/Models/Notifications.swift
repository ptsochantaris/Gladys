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
	static let LowMemoryModeOn = Notification.Name("LowMemoryModeOn")
	static let ItemModified = Notification.Name("ItemModified")
	static let LabelsUpdated = Notification.Name("LabelsUpdated")
	static let LabelSelectionChanged = Notification.Name("LabelSelectionChanged")
	static let DetailViewClosing = Notification.Name("DetailViewClosing")
	static let CloudManagerStatusChanged = Notification.Name("CloudManagerStatusChanged")
	static let ReachabilityChanged = Notification.Name("ReachabilityChanged")
	static let DarkModeChanged = Notification.Name("DarkModeChanged")
	static let IAPModeChanged = Notification.Name("IAPModeChanged")
	static let IngestComplete = Notification.Name("IngestComplete")
}
