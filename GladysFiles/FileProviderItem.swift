
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
		} else if let dropItem = dropItem {
			return NSNumber(value: dropItem.sizeInBytes)
		}
		return nil
	}

	var tagData: Data? {
		return dropItem?.tagData ?? typeItem?.tagData
	}

	var creationDate: Date? {
		return dropItem?.createdAt ?? typeItem?.createdAt
	}

	var isUploaded: Bool {
		return true
	}

	var isDownloaded: Bool {
		return true
	}

	var childItemCount: NSNumber? {
		if let dropItem = dropItem {
			return NSNumber(value: dropItem.typeItems.count)
		} else {
			return NSNumber(value: 0)
		}
	}

    var itemIdentifier: NSFileProviderItemIdentifier {
		if let dropItem = dropItem {
			return NSFileProviderItemIdentifier(dropItem.uuid.uuidString)
		} else if let typeItem = typeItem {
			return NSFileProviderItemIdentifier(typeItem.uuid.uuidString)
		} else {
			return NSFileProviderItemIdentifier.rootContainer
		}
    }
    
    var parentItemIdentifier: NSFileProviderItemIdentifier {
		if let typeItem = typeItem {
			return NSFileProviderItemIdentifier(typeItem.parentUuid.uuidString)
		} else {
			return NSFileProviderItemIdentifier.rootContainer
		}
    }
    
    var capabilities: NSFileProviderItemCapabilities {
		if typeItem != nil {
			return [.allowsReading]
		} else if dropItem != nil {
			return [.allowsReading, .allowsDeleting]
		} else {
			return [.allowsReading]
		}
    }
    
    var filename: String {
		if let dropItem = dropItem {
			return dropItem.oneTitle.replacingOccurrences(of: ".", with: " ")

		} else if let typeItem = typeItem {
			return typeItem.typeIdentifier.replacingOccurrences(of: ".", with: "-")

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
