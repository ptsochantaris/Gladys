//
//  Model+MessageCoordinator.swift
//  GladysMessage
//
//  Created by Paul Tsochantaris on 07/01/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension Model {

	private class ModelFilePresenter: NSObject, NSFilePresenter {

		var presentedItemURL: URL? {
			return Model.itemsDirectoryUrl
		}

		var presentedItemOperationQueue: OperationQueue {
			return OperationQueue.main
		}

		func presentedItemDidChange() {
			reloadDataIfNeeded()
		}
	}

	private static let messagesPresenter = ModelFilePresenter()

	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: nil)
	}

	static func prepareToSave() {}
	static func saveComplete() {}
	static func reloadCompleted() {
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
	}

	static func startupComplete() {
		NSFileCoordinator.addFilePresenter(messagesPresenter)
	}

	static var nonDeletedDrops: [ArchivedDropItem] {
		return drops.filter { !$0.needsDeletion }
	}
}
