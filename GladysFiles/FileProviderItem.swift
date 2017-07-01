
import FileProvider

final class FileProviderItem: NSObject, NSFileProviderItem {

	let item: ArchivedDropItem?
	let typeItem: ArchivedDropItemType?

	override init() { // root
		item = nil
		typeItem = nil
		super.init()
	}

	init(_ i: ArchivedDropItem) { // directory
		item = i
		typeItem = nil
		super.init()
	}

	init(_ i: ArchivedDropItemType) { // file
		item = nil
		typeItem = i
		super.init()
	}

	var documentSize: NSNumber? {
		if let typeItem = typeItem {
			return NSNumber(value: typeItem.sizeInBytes)
		} else if let item = item {
			return NSNumber(value: item.sizeInBytes)
		}
		return nil
	}

	var tagData: Data? {
		return item?.tagData ?? typeItem?.tagData
	}

	var creationDate: Date? {
		if let item = item {
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
		if let item = item {
			return NSNumber(value: item.typeItems.count)
		} else if typeItem != nil {
			return 0
		} else {
			return NSNumber(value: FileProviderExtension.model.drops.count)
		}
	}

    var itemIdentifier: NSFileProviderItemIdentifier {
		if let item = item {
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
		} else if item != nil {
			return [.allowsContentEnumerating, .allowsDeleting]
		} else {
			return [.allowsContentEnumerating]
		}
    }
    
    var filename: String {
		if let item = item {
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
