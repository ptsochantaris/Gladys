
import FileProvider
import UIKit

final class FileProviderExtension: NSFileProviderExtension {
    
    private var fileManager = FileManager()
	static let model = Model()

	override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
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

		throw NSError(domain: "build.bru.error", code: 2, userInfo: [ NSLocalizedDescriptionKey: "Could not find item with identifier \(identifier.rawValue)" ])
	}

    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        guard let fpi = (try? item(for: identifier)) as? FileProviderItem else {
            return nil
        }

		var root = NSFileProviderManager.default.documentStorageURL
		if let directoryItem = fpi.item {
			root.appendPathComponent(directoryItem.uuid.uuidString, isDirectory: true)
		} else if let fileItem = fpi.typeItem {
			root.appendPathComponent(fileItem.parentUuid.uuidString, isDirectory: true)
			root.appendPathComponent(fileItem.uuid.uuidString, isDirectory: true)
		}
        return root
    }
    
	override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
		let uuidString = url.lastPathComponent
		let identifier = NSFileProviderItemIdentifier(uuidString)
		if (try? item(for: identifier)) != nil {
			return identifier
		} else {
			return NSFileProviderItemIdentifier.rootContainer
		}
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
					if let fpi = (try? self.item(for: itemID)) as? FileProviderItem {
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
		let i = (try? item(for: containerItemIdentifier)) as? FileProviderItem
        return FileProviderEnumerator(relatedItem: i)
    }
    
}
