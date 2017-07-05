//
//  IndexRequestHandler.swift
//  GladysIndex
//
//  Created by Paul Tsochantaris on 21/06/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CoreSpotlight

final class IndexRequestHandler: CSIndexExtensionRequestHandler {

	private let model = Model()

    override func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
		model.reloadDataIfNeeded()
		model.searchableIndex(searchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler: acknowledgementHandler)
    }
    
    override func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
		model.reloadDataIfNeeded()
		model.searchableIndex(searchableIndex, reindexSearchableItemsWithIdentifiers: identifiers, acknowledgementHandler: acknowledgementHandler)
    }
    
    override func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {
		model.reloadDataIfNeeded()
		return try model.data(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier)
    }
    
    override func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
		model.reloadDataIfNeeded()
		return try model.fileURL(for: searchableIndex, itemIdentifier: itemIdentifier, typeIdentifier: typeIdentifier, inPlace: inPlace)
    }
}
