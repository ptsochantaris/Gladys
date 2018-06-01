//
//  Model+ImportExport.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 01/06/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import ZIPFoundation

extension Model {
	
	static func importData(from url: URL, completion: @escaping (Bool)->Void) {
		NSLog("URL for importing: \(url.path)")

		let fm = FileManager.default
		defer {
			try? fm.removeItem(at: url)
		}

		guard
			let data = try? Data(contentsOf: url.appendingPathComponent("items.json"), options: [.alwaysMapped]),
			let itemsInPackage = try? JSONDecoder().decode(Array<ArchivedDropItem>.self, from: data)
			else {
				completion(false)
				return
		}

		var itemsImported = 0

		for item in itemsInPackage.reversed() {

			if let i = drops.index(of: item) {
				if drops[i].updatedAt >= item.updatedAt {
					continue
				}
				drops[i] = item
			} else {
				drops.insert(item, at: 0)
			}

			itemsImported += 1
			item.needsReIngest = true
			item.markUpdated()

			let localPath = item.folderUrl
			if fm.fileExists(atPath: localPath.path) {
				try! fm.removeItem(at: localPath)
			}

			let remotePath = url.appendingPathComponent(item.uuid.uuidString)
			try! fm.moveItem(at: remotePath, to: localPath)

			item.cloudKitRecord = nil
			for typeItem in item.typeItems {
				typeItem.cloudKitRecord = nil
			}
		}

		DispatchQueue.main.async {
			if itemsImported > 0 {
				save()
				NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
			}
			completion(true)
		}
	}

	static var eligibleDropsForExport: [ArchivedDropItem] {
		let items = PersistedOptions.exportOnlyVisibleItems ? Model.threadSafeFilteredDrops : Model.threadSafeDrops
		return items.filter { $0.goodToSave }
	}

	private class FileManagerFilter: NSObject, FileManagerDelegate {
		func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool {
			let components = srcURL.pathComponents
			return !components.contains { $0 == "shared-blob" || $0 == "ck-record" }
		}
	}

	@discardableResult
	static func createArchive(completion: @escaping (URL)->Void) -> Progress {
		let eligibleItems = eligibleDropsForExport
		let count = 2 + eligibleItems.count
		let p = Progress(totalUnitCount: Int64(count))

		DispatchQueue.global(qos: .userInitiated).async {

			let fm = FileManager.default
			let tempPath = Model.temporaryDirectoryUrl.appendingPathComponent("Gladys Archive.gladysArchive")
			if fm.fileExists(atPath: tempPath.path) {
				try! fm.removeItem(at: tempPath)
			}

			var delegate: FileManagerFilter? = FileManagerFilter()
			fm.delegate = delegate

			p.completedUnitCount += 1

			try! fm.createDirectory(at: tempPath, withIntermediateDirectories: true, attributes: nil)
			for item in eligibleItems {
				let uuidString = item.uuid.uuidString
				let sourceForItem = Model.appStorageUrl.appendingPathComponent(uuidString)
				let destinationForItem = tempPath.appendingPathComponent(uuidString)
				try! fm.copyItem(at: sourceForItem, to: destinationForItem)
				p.completedUnitCount += 1
			}

			fm.delegate = nil
			delegate = nil

			let data = try! JSONEncoder().encode(eligibleItems)
			try! data.write(to: tempPath.appendingPathComponent("items.json"))
			p.completedUnitCount += 1

			completion(tempPath)
		}

		return p
	}

	@discardableResult
	static func createZip(completion: @escaping (URL)->Void) -> Progress {

		let dropsCopy = eligibleDropsForExport
		let itemCount = Int64(1 + dropsCopy.count)
		let p = Progress(totalUnitCount: itemCount)

		let tempPath = Model.temporaryDirectoryUrl.appendingPathComponent("Gladys.zip")

		DispatchQueue.global(qos: .userInitiated).async {

			let fm = FileManager.default
			if fm.fileExists(atPath: tempPath.path) {
				try! fm.removeItem(at: tempPath)
			}

			p.completedUnitCount += 1

			if let archive = Archive(url: tempPath, accessMode: .create) {
				for item in dropsCopy {
					let dir = item.displayTitleOrUuid.filenameSafe

					if item.typeItems.count == 1 {
						let typeItem = item.typeItems.first!
						self.addZipItem(typeItem, directory: nil, name: dir, in: archive)

					} else {
						for typeItem in item.typeItems {
							self.addZipItem(typeItem, directory: dir, name: typeItem.typeDescription, in: archive)
						}
					}
					p.completedUnitCount += 1
				}
			}

			completion(tempPath)
		}

		return p
	}

	static private func addZipItem(_ typeItem: ArchivedDropItemType, directory: String?, name: String, in archive: Archive) {

		var bytes: Data?
		if typeItem.isWebURL, let url = typeItem.encodedUrl, let data = url.urlFileContent {
			bytes = data

		} else if typeItem.classWasWrapped {
			bytes = typeItem.dataForWrappedItem ?? typeItem.bytes
		}
		if let B = bytes ?? typeItem.bytes {
			let timmedName = typeItem.prepareFilename(name: name, directory: directory)
			try? archive.addEntry(with: timmedName, type: .file, uncompressedSize: UInt32(B.count)) { pos, size -> Data in
				return B[pos ..< pos+size]
			}
		}
	}
}
