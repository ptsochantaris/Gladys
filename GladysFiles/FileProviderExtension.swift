
import FileProvider
import UIKit

final class FileProviderExtension: NSFileProviderExtension {
    
    private var fileManager = FileManager()
	static let model = Model()

    static func getItem(for identifier: NSFileProviderItemIdentifier) -> FileProviderItem? {

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

	override func fetchThumbnails(forItemIdentifiers itemIdentifiers: [NSFileProviderItemIdentifier], requestedSize size: CGSize, perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void, completionHandler: @escaping (Error?) -> Void) -> Progress {
		let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))
		DispatchQueue.global(qos: .background).async {
			for itemID in itemIdentifiers {
				autoreleasepool {
					if let fpi = FileProviderExtension.getItem(for: itemID) {
						if let dir = fpi.item, let img = dir.displayInfo.image {
							let scaledImage = img.limited(to: size)
							let data = UIImagePNGRepresentation(scaledImage)
							perThumbnailCompletionHandler(itemID, data, nil)
						} else if let file = fpi.typeItem, let img = file.displayIcon {
							let scaledImage = img.limited(to: size)
							let data = UIImagePNGRepresentation(scaledImage)
							perThumbnailCompletionHandler(itemID, data, nil)
						}
					}
					progress.completedUnitCount += 1
				}
			}
			completionHandler(nil)
		}
		return progress
	}
    
    // MARK: - Enumeration
    
    override func enumerator(forContainerItemIdentifier containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        let enumerator: NSFileProviderEnumerator
        if containerItemIdentifier == NSFileProviderItemIdentifier.rootContainer {
			enumerator = FileProviderEnumerator(enumeratedItemIdentifier: NSFileProviderItemIdentifier.rootContainer)
        } else if containerItemIdentifier == NSFileProviderItemIdentifier.workingSet {
			enumerator = FileProviderEnumerator(enumeratedItemIdentifier: NSFileProviderItemIdentifier.rootContainer)
        } else if containerItemIdentifier == NSFileProviderItemIdentifier.allDirectories {
			enumerator = FileProviderEnumerator(enumeratedItemIdentifier: NSFileProviderItemIdentifier.rootContainer)
        } else {
			enumerator = FileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier)
        }
        return enumerator
    }
    
}
