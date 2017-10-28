
import FileProvider
import UIKit

final class FileProviderExtension: NSFileProviderExtension {

	override init() {
		super.init()
		Model.ensureStarted()
	}

	@discardableResult
	override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {

		let uuid = UUID(uuidString: identifier.rawValue)

		let drops = Model.nonDeletedDrops

		for item in drops {
			if item.uuid == uuid {
				return FileProviderItem(item)
			}
		}

		for item in drops {
			for typeItem in item.typeItems {
				if typeItem.uuid == uuid {
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

	private func saveModel(completion: (()->Void)? = nil) {
		DispatchQueue.main.async {
			Model.oneTimeSaveCallback = completion
			Model.save()
		}
	}

    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
		do {
			if let fpi = try item(for: identifier) as? FileProviderItem {
				return fpi.fileSystemURL
			}
		} catch {
			log("Error getting URL for item with ID \(identifier): \(error.localizedDescription)")
		}
		return nil
    }

	private func fileItem(at url: URL) -> FileProviderItem? {
		let urlComponents = url.pathComponents
		if let lastComponent = urlComponents.last, urlComponents.count > 1 {
			if lastComponent == "items.json" || lastComponent == "ck-delete-queue" || lastComponent == "ck-uuid-sequence" {
				return nil
			}
			let uuidString = (lastComponent == "blob") ? urlComponents[urlComponents.count-2] : lastComponent
			let identifier = NSFileProviderItemIdentifier(uuidString)
			do {
				return try item(for: identifier) as? FileProviderItem
			} catch {
				log("Error locating file item at \(url): \(error.localizedDescription)")
			}
		}
		return nil
	}

	override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
		return fileItem(at: url)?.itemIdentifier
	}
    
    override func startProvidingItem(at url: URL, completionHandler: ((_ error: Error?) -> Void)?) {
		//log("Starting provision: \(url.path)")
		completionHandler?(nil)
    }

    override func itemChanged(at url: URL) {
		switch url.lastPathComponent {
		case "items.json", "ck-delete-queue", "ck-uuid-sequence":
			return
		default:
			log("Item changed: \(url.path)")
		}
		
		if let fi = fileItem(at: url), let typeItem = fi.typeItem, let parent = Model.nonDeletedDrops.first(where: { $0.uuid == typeItem.parentUuid }) {
			log("Identified as child of local item \(typeItem.parentUuid)")
			typeItem.markUpdated()
			parent.markUpdated()
			parent.needsReIngest = true
			saveModel()
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
				saveModel {
					completionHandler(i, nil)
				}
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
				saveModel {
					Model.signalWorkingSetChange()
					completionHandler(i, nil)
				}
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
			if let i = Model.drops.index(where: { $0.uuid == uuid }) {
				Model.drops[i].needsDeletion = true
				saveModel {
					completionHandler(nil)
				}
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
