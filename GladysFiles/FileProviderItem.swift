
import FileProvider

final class FileProviderItem: NSObject, NSFileProviderItem {

	let dropItem: ArchivedDropItem?
	let typeItem: ArchivedDropItemType?

	init(_ i: ArchivedDropItem) { // directory
		dropItem = i
		typeItem = nil
		super.init()
	}

	init(_ i: ArchivedDropItemType) { // file
		dropItem = nil
		typeItem = i
		super.init()
	}

	var documentSize: NSNumber? {
		if let typeItem = typeItem {
			return NSNumber(value: typeItem.sizeInBytes)
		} else if let item = dropItem {
			return NSNumber(value: item.sizeInBytes)
		}
		return nil
	}

	var tagData: Data? {
		return dropItem?.tagData ?? typeItem?.tagData
	}

	var creationDate: Date? {
		if let item = dropItem {
			return item.createdAt
		} else if let typeItem = typeItem {
			return typeItem.createdAt
		} else {
			return nil
		}
	}

	var isUploaded: Bool {
		return true
	}

	var isDownloaded: Bool {
		return true
	}

	var childItemCount: NSNumber? {
		if let item = dropItem {
			return NSNumber(value: item.typeItems.count)
		} else {
			return NSNumber(value: 0)
		}
	}

    var itemIdentifier: NSFileProviderItemIdentifier {
		if let item = dropItem {
			return NSFileProviderItemIdentifier(item.uuid.uuidString)
		} else if let typeItem = typeItem {
			return NSFileProviderItemIdentifier(typeItem.uuid.uuidString)
		} else {
			return NSFileProviderItemIdentifier.rootContainer
		}
    }
    
    var parentItemIdentifier: NSFileProviderItemIdentifier {
		if let typeItem = typeItem {
			return NSFileProviderItemIdentifier(typeItem.parentUuid.uuidString)
		}
		return NSFileProviderItemIdentifier.rootContainer
    }
    
    var capabilities: NSFileProviderItemCapabilities {
		if typeItem != nil {
			return [.allowsReading]
		} else if dropItem != nil {
			return [.allowsContentEnumerating, .allowsDeleting]
		} else {
			return [.allowsContentEnumerating]
		}
    }
    
    var filename: String {
		if let item = dropItem {
			return item.oneTitle
		} else if let typeItem = typeItem {
			var t = typeItem.typeIdentifier.replacingOccurrences(of: ".", with: "-")
			let c = t.components(separatedBy: "-")
			if c.count > 1, c.first == "public", let l = c.last {
				t = t.appending(".\(l)")
			}
			return t
		} else {
			return "<no name>"
		}
    }
    
    var typeIdentifier: String {
		if let typeItem = typeItem {
			return typeItem.typeIdentifier
		} else {
			return "public.folder"
		}
    }
}
