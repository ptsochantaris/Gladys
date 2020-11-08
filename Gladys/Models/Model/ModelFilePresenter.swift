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

	private let _presentedItemOperationQueue = OperationQueue()
	var presentedItemOperationQueue: OperationQueue {
		return _presentedItemOperationQueue // requests will be dispatched to main below
	}

	func presentedItemDidChange() {
		DispatchQueue.main.async {
            if Model.doneIngesting {
                Model.reloadDataIfNeeded()
            }
		}
	}
}
