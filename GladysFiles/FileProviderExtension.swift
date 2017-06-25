
import FileProvider

final class FileProviderExtension: NSFileProviderExtension {
    
    private var fileManager = FileManager()
	static let model = Model()

    static func getItem(for identifier: NSFileProviderItemIdentifier) -> FileProviderItem? {

		if identifier == NSFileProviderItemIdentifier.rootContainer {
			return FileProviderItem()
		} else {
			for item in FileProviderExtension.model.drops {
				if item.uuid.uuidString == identifier.rawValue {
					return FileProviderItem(item)
				}
				for typeItem in item.typeItems {
					if typeItem.uuid.uuidString == identifier.rawValue {
						return FileProviderItem(typeItem)
					}
				}
			}
		}

		return nil
    }
    
    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        guard let fpi = FileProviderExtension.getItem(for: identifier) else {
            return nil
        }

		var root = NSFileProviderManager.default.documentStorageURL
		if let directoryItem = fpi.item {
			root.appendPathComponent(directoryItem.uuid.uuidString, isDirectory: true)
		} else if let fileItem = fpi.typeItem {
			root.appendPathComponent(fileItem.parentUuid.uuidString, isDirectory: true)
			root.appendPathComponent(fileItem.uuid.uuidString, isDirectory: true)
			root.appendPathComponent("blob", isDirectory: false)
		}
        return root
    }
    
	override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
		if url.lastPathComponent == "blob" {
			if let c = url.pathComponents.dropLast().last {
				return NSFileProviderItemIdentifier(c)
			}
		} else if let c = url.pathComponents.last {
			return NSFileProviderItemIdentifier(c)
		}
		return NSFileProviderItemIdentifier.rootContainer
	}
    
    override func startProvidingItem(at url: URL, completionHandler: ((_ error: Error?) -> Void)?) {
		completionHandler?(nil)
    }

    override func itemChanged(at url: URL) {
    }
    
    override func stopProvidingItem(at url: URL) {
    }

	/*
	override func fetchThumbnails(forItemIdentifiers itemIdentifiers: [NSFileProviderItemIdentifier], requestedSize size: CGSize, perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void, completionHandler: @escaping (Error?) -> Void) -> Progress {
		for itemID in itemIdentifiers {
			if let item = FileProviderExtension.getItem(for: itemID) {
				if item
			} else {
				perThumbnailCompletionHandler(itemID, nil, nil)
			}
		}
		completionHandler(nil)
		return nil
	}
	*/
    
    // MARK: - Enumeration
    
    override func enumerator(forContainerItemIdentifier containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        var maybeEnumerator: NSFileProviderEnumerator? = nil
        if (containerItemIdentifier == NSFileProviderItemIdentifier.rootContainer) {
			maybeEnumerator = FileProviderEnumerator(enumeratedItemIdentifier: NSFileProviderItemIdentifier.rootContainer)
        } else if (containerItemIdentifier == NSFileProviderItemIdentifier.workingSet) {
			maybeEnumerator = FileProviderEnumerator(enumeratedItemIdentifier: NSFileProviderItemIdentifier.rootContainer)
        } else if (containerItemIdentifier == NSFileProviderItemIdentifier.allDirectories) {
			maybeEnumerator = FileProviderEnumerator(enumeratedItemIdentifier: nil)
        } else {
			maybeEnumerator = FileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier)
        }
        guard let enumerator = maybeEnumerator else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo:[:])
        }
        return enumerator
    }
    
}
