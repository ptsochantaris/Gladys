
import FileProvider
import UIKit

final class FileProviderExtension: NSFileProviderExtension {
    
    private var fileManager = FileManager()
	static let model = Model()

	override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {

		let dropsCopy = FileProviderExtension.model.drops
		let uuid = identifier.rawValue

		for item in dropsCopy {
			if item.uuid.uuidString == uuid {
				return FileProviderItem(item)
			}
		}

		for item in dropsCopy {
			for typeItem in item.typeItems {
				if typeItem.uuid.uuidString == uuid {
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
			root.appendPathComponent("blob", isDirectory: false)
		}
        return root
    }
    
	override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
		let urlComponents = url.pathComponents
		if let lastComponent = urlComponents.last, urlComponents.count > 2 {
			let uuidString = (lastComponent == "blob") ? urlComponents[urlComponents.count-2] : lastComponent
			let identifier = NSFileProviderItemIdentifier(uuidString)
			if (try? item(for: identifier)) != nil {
				return identifier
			}
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

	private func imageData(img: UIImage, size: CGSize, contentMode: ArchivedDropItemDisplayType) -> Data? {
		let shouldHalve = contentMode == .center || contentMode == .circle
		let scaledImage = img.limited(to: size, shouldHalve: shouldHalve)
		return UIImagePNGRepresentation(scaledImage)
	}

	override func fetchThumbnails(forItemIdentifiers itemIdentifiers: [NSFileProviderItemIdentifier], requestedSize size: CGSize, perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void, completionHandler: @escaping (Error?) -> Void) -> Progress {
		let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))

		let queue = DispatchQueue(label: "build.bru.thumbnails", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)
		queue.async {
			let mySize = CGSize(width: 256, height: 256)
			for itemID in itemIdentifiers {
				autoreleasepool {
					NSLog("Creating thumbnail for item \(itemID.rawValue)")
					if let fpi = (try? self.item(for: itemID)) as? FileProviderItem {
						if let dir = fpi.item, let img = dir.displayInfo.image {
							let data = self.imageData(img: img, size: mySize, contentMode: dir.displayInfo.imageContentMode)
							perThumbnailCompletionHandler(itemID, data, nil)
						} else if let file = fpi.typeItem, let img = file.displayIcon {
							let data = self.imageData(img: img, size: mySize, contentMode: file.displayIconContentMode)
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

	deinit {
		NSLog("File extension terminated")
	}

    // MARK: - Enumeration

    override func enumerator(forContainerItemIdentifier containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
		let i = (try? item(for: containerItemIdentifier)) as? FileProviderItem
        return FileProviderEnumerator(relatedItem: i)
    }
    
}
