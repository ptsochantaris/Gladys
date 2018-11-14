
import FileProvider

final class RootItem: NSObject, NSFileProviderItem {

	var itemIdentifier: NSFileProviderItemIdentifier {
		return NSFileProviderItemIdentifier.rootContainer
	}

	var parentItemIdentifier: NSFileProviderItemIdentifier {
		return NSFileProviderItemIdentifier.rootContainer
	}

	var filename: String {
		return "Gladys Items"
	}

	var typeIdentifier: String {
		return "public.folder"
	}

	var childItemCount: NSNumber? {
		return NSNumber(value: Model.visibleDrops.count)
	}
}

final class FileProviderItem: NSObject, NSFileProviderItem {

	let dropItem: ArchivedDropItem?
	let typeItem: ArchivedDropItemType?

	init(_ i: ArchivedDropItem) {
		let count = i.typeItems.count
		if count == 1 {
			dropItem = i
			typeItem = i.typeItems.first
		} else {
			dropItem = i
			typeItem = nil
		}
		super.init()
	}

	init(_ i: ArchivedDropItemType) {
		dropItem = nil
		typeItem = i
		super.init()
	}

	var fileSystemURL: URL? {
		return typeItem?.sharedLink ?? dropItem?.folderUrl
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

	var favoriteRank: NSNumber? {
		return dropItem?.favoriteRank
	}

	var creationDate: Date? {
		return dropItem?.createdAt ?? typeItem?.createdAt
	}

	var contentModificationDate: Date? {
		return dropItem?.updatedAt ?? typeItem?.updatedAt
	}

	var gladysModificationDate: Date {
		var date = contentModificationDate ?? .distantPast

		// tags
		if dropItem?.hasTagData ?? false, let path = dropItem?.tagDataPath, let d = Model.modificationDate(for: path) {
			date = max(date, d)
		} else if typeItem?.hasTagData ?? false, let path = typeItem?.tagDataPath, let d = Model.modificationDate(for: path) {
			date = max(date, d)
		}

		// previews
		if let dropItem = dropItem {
			for typeItem in dropItem.typeItems {
				date = max(date, typeItem.updatedAt) // if child is fresher, use that date
				if let d = Model.modificationDate(for: typeItem.bytesPath) {
					date = max(date, d)
				}
			}
		} else if let typeItem = typeItem, let d = Model.modificationDate(for: typeItem.bytesPath) {
			date = max(date, d)
		}

		return date
	}

	var versionIdentifier: Data? {
		return String(gladysModificationDate.timeIntervalSinceReferenceDate).data(using: .utf8)
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
			let count = dropItem.typeItems.count
			if count == 1 {
				return NSNumber(value: 0)
			}
			return NSNumber(value: count)
		} else {
			return NSNumber(value: 0)
		}
	}

    var itemIdentifier: NSFileProviderItemIdentifier {
		if let typeItem = typeItem {
			return NSFileProviderItemIdentifier(typeItem.uuid.uuidString)
		} else if let dropItem = dropItem {
			return NSFileProviderItemIdentifier(dropItem.uuid.uuidString)
		} else {
			return NSFileProviderItemIdentifier.rootContainer
		}
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
		if dropItem == nil, let p = typeItem?.parentUuid {
			return NSFileProviderItemIdentifier(p.uuidString)
		} else {
			return NSFileProviderItemIdentifier.rootContainer
		}
    }
    
    var capabilities: NSFileProviderItemCapabilities {
		if let t = typeItem, let parent = Model.item(uuid: t.parentUuid) {
			if parent.shareMode == .elsewhereReadOnly {
				return [.allowsReading]
			} else {
				return [.allowsReading, .allowsWriting, .allowsDeleting]
			}
		} else if dropItem != nil {
			return [.allowsReading, .allowsDeleting]
		} else {
			return [.allowsReading]
		}
    }

    var filename: String {
		if let d = dropItem {
			return d.displayTitleOrUuid

		} else if let typeItem = typeItem {

			let filename = typeItem.typeDescription
			if let e = typeItem.fileExtension {
				return "\(filename).\(e)"
			}
			return filename

		} else {
			return "<no name>"
		}
    }
    
    var typeIdentifier: String {
		return typeItem?.typeIdentifier ?? "public.folder"
    }
}
