//
//  ModelFilePresenter.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/01/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

final class ModelFilePresenter: NSObject, NSFilePresenter {

	var presentedItemURL: URL? {
		return Model.itemsDirectoryUrl
	}

	var presentedItemOperationQueue: OperationQueue {
		return OperationQueue.main
	}

	func presentedItemDidChange() {
		OperationQueue.main.addOperation {
			Model.reloadDataIfNeeded()
		}
	}
}
