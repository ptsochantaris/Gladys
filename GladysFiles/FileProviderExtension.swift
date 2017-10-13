
import FileProvider
import UIKit

let model = Model()

final class FileProviderExtension: NSFileProviderExtension {

	override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {

		let uuid = identifier.rawValue

		for item in model.drops {
			if item.uuid.uuidString == uuid {
				return FileProviderItem(item)
			}
		}

		for item in model.drops {
			for typeItem in item.typeItems {
				if typeItem.uuid.uuidString == uuid {
					if item.typeItems.count == 1 {
						return FileProviderItem(item)
					} else {
						return FileProviderItem(typeItem)
					}
				}
			}
		}

		throw NSFileProviderError(.noSuchItem)
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
		//log("Starting provision: \(url.path)")
		completionHandler?(nil)
    }

	override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
		log("Providing placeholder: \(url.path)")

		guard let identifier = persistentIdentifierForItem(at: url) else {
			completionHandler(NSFileProviderError(.noSuchItem))
			return
		}

		do {
			let fileProviderItem = try item(for: identifier)
			let placeholderURL = NSFileProviderManager.placeholderURL(for: url)
			try NSFileProviderManager.writePlaceholder(at: placeholderURL, withMetadata: fileProviderItem)
			completionHandler(nil)
		}
		catch let error {
			completionHandler(error)
		}
	}

    override func itemChanged(at url: URL) {
		if url.lastPathComponent == "items.json" { return }
		log("Item changed: \(url.path)")
		if let fi = fileItem(at: url), let typeItem = fi.typeItem, let parent = model.drops.first(where: { $0.uuid == typeItem.parentUuid }) {
			log("Identified as child of local item \(typeItem.parentUuid)")
			parent.needsReIngest = true
			model.save()
		}
    }

    override func stopProvidingItem(at url: URL) {
		//log("Stopping provision: \(url.path)")
    }

	private func imageData(img: UIImage, size: CGSize, contentMode: ArchivedDropItemDisplayType) -> Data? {
		let limit: CGFloat = (contentMode == .center || contentMode == .circle) ? 0.5 : 0.9
		let scaledImage = img.limited(to: size, limitTo: limit)
		return UIImagePNGRepresentation(scaledImage)
	}

	override func setFavoriteRank(_ favoriteRank: NSNumber?, forItemIdentifier itemIdentifier: NSFileProviderItemIdentifier, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
		do {
			if let i = try item(for: itemIdentifier) as? FileProviderItem {
				i.dropItem?.favoriteRank = favoriteRank
				model.save()
				completionHandler(i, nil)
			} else {
				completionHandler(nil, NSFileProviderError(.noSuchItem))
			}
		} catch {
			completionHandler(nil, error)
		}
	}

	override func setTagData(_ tagData: Data?, forItemIdentifier itemIdentifier: NSFileProviderItemIdentifier, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
		do {
			if let i = try item(for: itemIdentifier) as? FileProviderItem {
				i.dropItem?.tagData = tagData
				i.typeItem?.tagData = tagData
				model.save()
				completionHandler(i, nil)
			} else {
				completionHandler(nil, NSFileProviderError(.noSuchItem))
			}
		} catch {
			completionHandler(nil, error)
		}
	}

	override func fetchThumbnails(for itemIdentifiers: [NSFileProviderItemIdentifier], requestedSize size: CGSize, perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void, completionHandler: @escaping (Error?) -> Void) -> Progress {
		let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))

		DispatchQueue.global(qos: .background).async {
			let mySize = CGSize(width: 256, height: 256)
			for itemID in itemIdentifiers {
				autoreleasepool {
					log("Creating thumbnail for item \(itemID.rawValue)")
					var data: Data?
					if let fpi = (try? self.item(for: itemID)) as? FileProviderItem {
						if let dir = fpi.dropItem {
							data = self.imageData(img: dir.displayIcon, size: mySize, contentMode: dir.displayMode)
						} else if let file = fpi.typeItem, let img = file.displayIcon {
							data = self.imageData(img: img, size: mySize, contentMode: file.displayIconContentMode)
						}
					}
					perThumbnailCompletionHandler(itemID, data, nil)
					progress.completedUnitCount += 1
				}
			}
			completionHandler(nil)
		}

		return progress
	}

	override func deleteItem(withIdentifier itemIdentifier: NSFileProviderItemIdentifier, completionHandler: @escaping (Error?) -> Void) {
		do {
			guard let fpi = try item(for: itemIdentifier) as? FileProviderItem else {
				completionHandler(NSFileProviderError(.noSuchItem))
				return
			}
			guard let uuid = fpi.dropItem?.uuid ?? fpi.typeItem?.parentUuid else {
				completionHandler(NSFileProviderError(.noSuchItem))
				return
			}
			if let i = model.drops.index(where: { $0.uuid == uuid }) {
				model.drops.remove(at: i)
				model.save()
				completionHandler(nil)
			} else {
				completionHandler(NSFileProviderError(.noSuchItem))
			}
		} catch {
			completionHandler(error)
		}
	}

	deinit {
		log("File extension terminated")
	}

    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {

		switch containerItemIdentifier {
		case .workingSet:
			return WorkingSetEnumerator()
		case .rootContainer:
			return RootEnumerator()
		default:
			if let i = ((try? item(for: containerItemIdentifier)) as? FileProviderItem)?.dropItem {
				return DropItemEnumerator(dropItem: i)
			} else {
				throw NSFileProviderError(.noSuchItem)
			}
		}
    }
}
