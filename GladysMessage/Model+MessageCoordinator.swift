//
//  Model+MessageCoordinator.swift
//  GladysMessage
//
//  Created by Paul Tsochantaris on 07/01/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension Model {

	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: nil)
	}

	static func prepareToSave() {}
	static func saveComplete() {}
	static func startupComplete() {}
	static func reloadCompleted() {
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
	}
}
