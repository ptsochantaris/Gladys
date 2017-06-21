//
//  IndexRequestHandler.swift
//  GladysIndex
//
//  Created by Paul Tsochantaris on 21/06/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CoreSpotlight

class IndexRequestHandler: CSIndexExtensionRequestHandler {

    override func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
        // Reindex all data with the provided index
        
        acknowledgementHandler()
    }
    
    override func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
        // Reindex any items with the given identifiers and the provided index
        
        acknowledgementHandler()
    }
    
    override func data(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String) throws -> Data {

		let model = Model()
		if let item = model.drops.filter({ $0.uuid.uuidString == itemIdentifier }).first,
			let data = item.bytes(for: typeIdentifier) {

			return data
		}
        return Data()
    }
    
    override func fileURL(for searchableIndex: CSSearchableIndex, itemIdentifier: String, typeIdentifier: String, inPlace: Bool) throws -> URL {
		
		let model = Model()
		if let item = model.drops.filter({ $0.uuid.uuidString == itemIdentifier }).first,
			let url = item.url(for: typeIdentifier) {
			return url as URL
		}
        return URL(string:"file://")!
    }
    
}
