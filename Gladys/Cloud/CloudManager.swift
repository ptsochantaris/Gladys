//
//  CloudManager.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 21/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CloudKit

let diskSizeFormatter = ByteCountFormatter()

extension Array {
	func bunch(maxSize: Int) -> [[Element]] {
		var pos = 0
		var res = [[Element]]()
		while pos < count {
			let end = Swift.min(count, pos + maxSize)
			let a = self[pos ..< end]
			res.append(Array(a))
			pos += maxSize
		}
		return res
	}
}

extension Array where Element == [CKRecord] {
	func flatBunch(minSize: Int) -> [[CKRecord]] {
		var result = [[CKRecord]]()
		var newChild = [CKRecord]()
		for childArray in self {
			newChild.append(contentsOf: childArray)
			if newChild.count >= minSize {
				result.append(newChild)
				newChild.removeAll(keepingCapacity: true)
			}
		}
		if !newChild.isEmpty {
			result.append(newChild)
		}
		return result
	}
}

extension Error {
	var itemDoesNotExistOnServer: Bool {
		return (self as? CKError)?.code == CKError.Code.unknownItem
	}
}

final class CloudManager {

	struct RecordType {
		static let item = "ArchivedDropItem"
		static let component = "ArchivedDropItemType"
		static let positionList = "PositionList"
		static let share = "cloudkit.share"
        static let extensionUpdate = "ExtensionUpdate"
	}
	
	static let container = CKContainer(identifier: "iCloud.build.bru.Gladys")
    
    static var syncSwitchedOn: Bool {
        get {
            return PersistedOptions.defaults.bool(forKey: "syncSwitchedOn")
        }

        set {
            PersistedOptions.defaults.set(newValue, forKey: "syncSwitchedOn")
        }
    }
}
