import Foundation

final class FileAreaManager {
    static let appDocumentsUrl: URL = {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Mirrored Files")
    }()
    
    static func mirrorBlobsToFiles() {
        for item in Model.drops where item.goodToSave {
            item.mirrorBlobToFiles()
        }
    }
}

extension ArchivedDropItem {
    func mirrorBlobToFiles() {
        let f = FileManager.default
        
        let parentUrl: URL = FileAreaManager.appDocumentsUrl.appendingPathComponent(displayTitleOrUuid.dropFilenameSafe.truncate(limit: 32))
        do {
            if typeItems.count == 1, let child = typeItems.first {
                try child.mirror(to: parentUrl, asChild: false, using: f)
            } else {
                try f.createDirectory(at: parentUrl, withIntermediateDirectories: true, attributes: nil)
                for child in typeItems {
                    try child.mirror(to: parentUrl, asChild: true, using: f)
                }
            }
        } catch {
            log("Error while mirroring item \(uuid) to file area: \(error.localizedDescription)")
        }
    }
}

extension ArchivedDropItemType {
    func mirror(to parentUrl: URL, asChild: Bool, using f: FileManager) throws {
        if !f.fileExists(atPath: bytesPath.path) {
            return
        }

        var url = asChild ? parentUrl.appendingPathComponent(filenameTypeIdentifier) : parentUrl
        
        if let ext = fileExtension {
            url = url.appendingPathExtension(ext)
        }
        
        let path = url.path
        if f.fileExists(atPath: path) {
            try f.removeItem(at: url)
        }
        try f.copyItem(at: bytesPath, to: url)
        try f.setAttributes([.extensionHidden: false, .type: typeIdentifier], ofItemAtPath: path)
    }
}

/*
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
*/
