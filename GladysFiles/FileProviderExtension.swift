
import FileProvider
import UIKit

final class FileProviderExtension: NSFileProviderExtension {
    
	private let model = Model()

	override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {

		let dropsCopy = model.drops
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

		throw NSError(domain: "build.bru.Gladys.error", code: 2, userInfo: [ NSLocalizedDescriptionKey: "Could not find item with identifier \(identifier.rawValue)" ])
	}

    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        guard let fpi = (try? item(for: identifier)) as? FileProviderItem else {
            return nil
        }

		if let directoryItem = fpi.dropItem {
			return directoryItem.folderUrl
		} else if let fileItem = fpi.typeItem {
			return fileItem.bytesPath
		} else {
			return Model.appStorageUrl
		}
    }

	private func fileItem(at url: URL) -> FileProviderItem? {
		let urlComponents = url.pathComponents
		if let lastComponent = urlComponents.last, urlComponents.count > 2 {
			let uuidString = (lastComponent == "blob") ? urlComponents[urlComponents.count-2] : lastComponent
			let identifier = NSFileProviderItemIdentifier(uuidString)
			return (try? item(for: identifier)) as? FileProviderItem
		}
		return nil
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
		log("Starting provision: \(url.path)")
		completionHandler?(nil)
    }

    override func itemChanged(at url: URL) {
		if url.lastPathComponent == "items.json" { return }
		log("Item changed: \(url.path)")
		if let fi = fileItem(at: url), let parentUuid = fi.typeItem?.parentUuid, let parent = model.drops.first(where: { $0.uuid == parentUuid }) {
			log("Identified as child of local item \(parent.uuid)")
			parent.needsReIngest = true
			parent.updatedAt = Date()
			model.save()
			return
		}
    }

    override func stopProvidingItem(at url: URL) {
		log("Stopping provision: \(url.path)")
    }

	private func imageData(img: UIImage, size: CGSize, contentMode: ArchivedDropItemDisplayType) -> Data? {
		let limit: CGFloat = (contentMode == .center || contentMode == .circle) ? 0.5 : 0.9
		let scaledImage = img.limited(to: size, limitTo: limit)
		return UIImagePNGRepresentation(scaledImage)
	}

	override func setTagData(_ tagData: Data?, forItemIdentifier itemIdentifier: NSFileProviderItemIdentifier, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
		if let i = (try? item(for: itemIdentifier)) as? FileProviderItem {
			i.dropItem?.tagData = tagData
			i.typeItem?.tagData = tagData
			model.save()
		}
	}

	override func fetchThumbnails(for itemIdentifiers: [NSFileProviderItemIdentifier], requestedSize size: CGSize, perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void, completionHandler: @escaping (Error?) -> Void) -> Progress {
		let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))

		let queue = DispatchQueue(label: "build.bru.thumbnails", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)
		queue.async {
			let mySize = CGSize(width: 256, height: 256)
			for itemID in itemIdentifiers {
				autoreleasepool {
					log("Creating thumbnail for item \(itemID.rawValue)")
					if let fpi = (try? self.item(for: itemID)) as? FileProviderItem {
						if let dir = fpi.dropItem {
							let data = self.imageData(img: dir.displayIcon, size: mySize, contentMode: dir.displayMode)
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

	override func deleteItem(withIdentifier itemIdentifier: NSFileProviderItemIdentifier, completionHandler: @escaping (Error?) -> Void) {
		guard let fpi = (try? item(for: itemIdentifier)) as? FileProviderItem else {
			completionHandler(NSError(domain: "build.bru.Gladys.error", code: 15, userInfo: [ NSLocalizedDescriptionKey: "Item not found" ]))
			return
		}
		guard let dir = fpi.dropItem else {
			completionHandler(NSError(domain: "build.bru.Gladys.error", code: 18, userInfo: [ NSLocalizedDescriptionKey: "Item not deletable" ]))
			return
		}
		if let i = model.drops.index(where: { $0 === dir }) {
			model.drops.remove(at: i)
			model.save()
		}
	}

	deinit {
		log("File extension terminated")
	}

    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {

		switch containerItemIdentifier {
		case .workingSet, .rootContainer:
			return FileProviderEnumerator(relatedItem: nil, model: model)
		default:
			let i = (try? item(for: containerItemIdentifier)) as? FileProviderItem
			return FileProviderEnumerator(relatedItem: i, model: model)
		}
    }
    
}
