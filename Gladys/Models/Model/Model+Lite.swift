//
//  Model+Lite.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 15/11/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension Model {

	static func countSavedItemsWithoutLoading() -> Int {
		if brokenMode {
			log("Ignoring count, model is broken, app needs restart.")
			return 0
		}

		var count = 0
		var coordinationError: NSError?
		var loadingError : NSError?

		coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

			let fm = FileManager.default
			if !fm.fileExists(atPath: url.path) {
				return
			}

			do {
				let uuidFileURL = url.appendingPathComponent("uuids")
				do {
					if let fileSize = try fm.attributesOfItem(atPath: uuidFileURL.path)[FileAttributeKey.size] as? UInt64 {
						if fileSize % 16 != 0 {
							log("Warning: uuid file size not multiple of 16!")
						}
						count = Int(fileSize / 16)
					} else {
						log("Could not parse the size of uuid file")
					}
				} catch {
					log("Loading Error: \(error)")
					loadingError = error as NSError
				}
			}
		}

		if let e = loadingError ?? coordinationError {
			log("Error in counting saved items: \(e)")
		}

		return count
	}

	static func locateItemWithoutLoading(uuid: String) -> ArchivedDropItem? {
		if brokenMode {
			log("Ignoring locate operation, model is broken, app needs restart.")
			return nil
		}

		var item: ArchivedDropItem?
		var coordinationError: NSError?

		coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

			let fm = FileManager.default
			if !fm.fileExists(atPath: url.path) {
				return
			}

			let dataPath = url.appendingPathComponent(uuid)
			if let data = try? Data(contentsOf: dataPath) {
				item = try? loadDecoder.decode(ArchivedDropItem.self, from: data)
			}
		}

		if let e = coordinationError {
			log("Error in searching through saved items: \(e)")
		}

		return item
	}

	static func locateComponentWithoutLoading(uuid: String) -> (ArchivedDropItem, ArchivedDropItemType)? {
		if brokenMode {
			log("Ignoring locate component operation, model is broken, app needs restart.")
			return nil
		}

		var result: (ArchivedDropItem, ArchivedDropItemType)?
		let uuidData = UUID(uuidString: uuid)

		iterateThroughSavedItemsWithoutLoading { item in
			if let component = item.typeItems.first(where: { $0.uuid == uuidData }) {
				result = (item, component)
				return false
			}
			return true
		}
		return result
	}

	private static func iterateThroughSavedItemsWithoutLoading(perItemCallback: (ArchivedDropItem) -> Bool) {
		if brokenMode {
			log("Ignoring search operation, model is broken, app needs restart.")
			return
		}

		var coordinationError: NSError?
		var loadingError : NSError?

		coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

			if !FileManager.default.fileExists(atPath: url.path) {
				return
			}

			do {
				let d = try Data(contentsOf: url.appendingPathComponent("uuids"))
				var c = 0
				var go = true
				while c < d.count && go {
					autoreleasepool {
						let u = UUID(uuid: (d[c], d[c+1], d[c+2], d[c+3], d[c+4], d[c+5],
											d[c+6], d[c+7], d[c+8], d[c+9], d[c+10], d[c+11],
											d[c+12], d[c+13], d[c+14], d[c+15]))
						c += 16
						let dataPath = url.appendingPathComponent(u.uuidString)
						if let data = try? Data(contentsOf: dataPath), let item = try? loadDecoder.decode(ArchivedDropItem.self, from: data) {
							go = perItemCallback(item)
						}
					}
				}
			} catch {
				log("Loading Error: \(error)")
				loadingError = error as NSError
			}
		}

		if let e = loadingError ?? coordinationError {
			log("Error in searching through saved items for a component: \(e)")
		}
	}

	static func insertNewItemsWithoutLoading(items: [ArchivedDropItem], addToDrops: Bool) {
		if items.isEmpty { return }

		if brokenMode {
			log("Ignoring insert operation, model is broken, app needs restart.")
			return
		}

		var closureError: NSError?
		var coordinationError: NSError?
		coordinator.coordinate(writingItemAt: itemsDirectoryUrl, options: [], error: &coordinationError) { url in
			do {
				let fm = FileManager.default
				var uuidData: Data
				if fm.fileExists(atPath: url.path) {
					uuidData = try Data(contentsOf: url.appendingPathComponent("uuids"))
				} else {
					try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
					uuidData = Data()
				}

				for item in items {
					item.isBeingCreatedBySync = false
					item.needsSaving = false
					let u = item.uuid
					let t = u.uuid
                    let finalPath = url.appendingPathComponent(u.uuidString)
					try saveEncoder.encode(item).write(to: finalPath, options: [])
					uuidData.insert(contentsOf: [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15], at: 0)
				}
				try uuidData.write(to: url.appendingPathComponent("uuids"), options: .atomic)

			} catch {
				closureError = error as NSError
			}
			// do not update last modified date, as there may be external changes that need to be loaded additionally later as well
		}
		if let e = coordinationError ?? closureError {
			log("Error inserting new item into saved data store: \(e.localizedDescription)")
		} else if addToDrops {
			drops.append(contentsOf: items)
		}
	}

	static func commitExistingItemsWithoutLoading(_ items: [ArchivedDropItem]) {
		if items.isEmpty { return }

		if brokenMode {
			log("Ignoring commit operation, model is broken, app needs restart.")
			return
		}

		var closureError: NSError?
		var coordinationError: NSError?
		coordinator.coordinate(writingItemAt: itemsDirectoryUrl, options: [], error: &coordinationError) { url in
			do {
				for item in items {
					item.needsSaving = false
					item.isBeingCreatedBySync = false
                    let finalPath = url.appendingPathComponent(item.uuid.uuidString)
					try saveEncoder.encode(item).write(to: finalPath, options: [])
				}
			} catch {
				closureError = error as NSError
			}
			// do not update last modified date, as there may be external changes that need to be loaded additionally later as well
		}
		if let e = coordinationError ?? closureError {
			log("Error updating item in saved data store: \(e.localizedDescription)")
		}
	}
}
