//
//  CloudManager.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 21/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import CloudKit

let diskSizeFormatter = ByteCountFormatter()

extension Sequence where Element: Hashable {
    var uniqued: [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}
extension Array {
	func bunch(maxSize: Int) -> [[Element]] {
		var pos = 0
		var slices = [ArraySlice<Element>]()
		while pos < count {
			let end = Swift.min(count, pos + maxSize)
            slices.append(self[pos ..< end])
			pos += maxSize
		}
        return slices.map { Array($0) }
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

    enum RecordType: String {
		case item = "ArchivedDropItem"
		case component = "ArchivedDropItemType"
		case positionList = "PositionList"
		case share = "cloudkit.share"
        case extensionUpdate = "ExtensionUpdate"
	}
	
	static let container = CKContainer(identifier: "iCloud.build.bru.Gladys")
    
    @UserDefault(key: "syncSwitchedOn", defaultValue: false)
    static var syncSwitchedOn: Bool
}
