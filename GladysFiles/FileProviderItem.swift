
import FileProvider

final class FileProviderItem: NSObject, NSFileProviderItem {

	let dropItem: ArchivedDropItem?
	let typeItem: ArchivedDropItemType?
	private let parentUUID: UUID?
	private var titleOverride: String

	init(_ i: ArchivedDropItem) {
		titleOverride = i.oneTitle.replacingOccurrences(of: ".", with: " ")
		if i.typeItems.count == 1 {
			dropItem = nil
			typeItem = i.typeItems.first
		} else {
			dropItem = i
			typeItem = nil
		}
		parentUUID = nil
		super.init()
	}

	init(_ i: ArchivedDropItemType) {
		titleOverride = i.oneTitle.replacingOccurrences(of: ".", with: " ")
		dropItem = nil
		typeItem = i
		parentUUID = i.parentUuid
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

	var contentModificationDate: Date? {
		return dropItem?.updatedAt ?? typeItem?.updatedAt
	}

	var versionIdentifier: Data? {
		if let m = contentModificationDate {
			return String(m.timeIntervalSinceReferenceDate).data(using: .utf8)
		}
		return nil
	}

	var isMostRecentVersionDownloaded: Bool {
		return true
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
		if let p = parentUUID {
			return NSFileProviderItemIdentifier(p.uuidString)
		} else {
			return NSFileProviderItemIdentifier.rootContainer
		}
    }
    
    var capabilities: NSFileProviderItemCapabilities {
		if typeItem != nil {
			if parentUUID == nil {
				return [.allowsReading, .allowsWriting, .allowsDeleting]
			} else {
				return [.allowsReading, .allowsWriting]
			}
		} else if dropItem != nil {
			return [.allowsReading, .allowsDeleting]
		} else {
			return [.allowsReading]
		}
    }

    var filename: String {
		if dropItem != nil {
			return titleOverride

		} else if let typeItem = typeItem {
			if parentUUID == nil {
				return titleOverride

			} else {
				let filename = typeItem.contentDescription
				if let e = typeItem.fileExtension {
					return "\(filename).\(e)"
				}
				return filename
			}

		} else {
			return "<no name>"
		}
    }
    
    var typeIdentifier: String {
		return typeItem?.typeIdentifier ?? "public.folder"
    }
}
