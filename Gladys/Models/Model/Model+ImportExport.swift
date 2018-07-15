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

	private static func bringInItem(_ item: ArchivedDropItem, from url: URL, using fm: FileManager, moveItem: Bool) throws -> Bool {

		let remotePath = url.appendingPathComponent(item.uuid.uuidString)
		if !fm.fileExists(atPath: remotePath.path) {
			log("Warning: Item \(item.uuid) declared but not found on imported archive, skipped")
			return false
		}

		if moveItem {
			try fm.moveAndReplaceItem(at: remotePath, to: item.folderUrl)
		} else {
			try fm.copyAndReplaceItem(at: remotePath, to: item.folderUrl)
		}

		item.needsReIngest = true
		item.markUpdated()
		item.removeFromCloudkit()
		
		return true
	}

	static func importData(from url: URL, removingOriginal: Bool) throws {
		let fm = FileManager.default
		defer {
			if removingOriginal {
				try? fm.removeItem(at: url)
			}
			save()
			NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
		}

		let data = try Data(contentsOf: url.appendingPathComponent("items.json"), options: [.alwaysMapped])
		let itemsInPackage = try JSONDecoder().decode(Array<ArchivedDropItem>.self, from: data)

		for item in itemsInPackage.reversed() {
			if let i = drops.index(of: item) {
				if drops[i].updatedAt >= item.updatedAt || drops[i].shareMode != .none {
					continue
				}
				if try bringInItem(item, from: url, using: fm, moveItem: removingOriginal) {
					drops[i] = item
				}
			} else {
				if try bringInItem(item, from: url, using: fm, moveItem: removingOriginal) {
					drops.insert(item, at: 0)
				}
			}
		}
	}

	static var eligibleDropsForExport: [ArchivedDropItem] {
		let items = PersistedOptions.exportOnlyVisibleItems ? Model.threadSafeFilteredDrops : Model.threadSafeDrops
		return items.filter { $0.goodToSave }
	}

	private class FileManagerFilter: NSObject, FileManagerDelegate {
		func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool {
			let components = srcURL.pathComponents
			return !components.contains { $0 == "shared-blob" || $0 == "ck-record" || $0 == "ck-share" }
		}
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	@discardableResult
	static func createArchive(completion: @escaping (URL?, Error?) -> Void) -> Progress {
		let eligibleItems = eligibleDropsForExport.filter { !$0.isImportedShare }
		let count = 2 + eligibleItems.count
		let p = Progress(totalUnitCount: Int64(count))

		DispatchQueue.global(qos: .userInitiated).async {
			do {
				try createArchiveThread(progress: p, eligibleItems: eligibleItems, completion: completion)
			} catch {
				completion(nil, error)
			}
		}

		return p
	}

	static private func createArchiveThread(progress p: Progress, eligibleItems: [ArchivedDropItem], completion: @escaping (URL?, Error?) -> Void) throws {
		let fm = FileManager.default
		let tempPath = Model.temporaryDirectoryUrl.appendingPathComponent("Gladys Archive.gladysArchive")
		if fm.fileExists(atPath: tempPath.path) {
			try fm.removeItem(at: tempPath)
		}

		var delegate: FileManagerFilter? = FileManagerFilter()
		fm.delegate = delegate

		p.completedUnitCount += 1

		try fm.createDirectory(at: tempPath, withIntermediateDirectories: true, attributes: nil)
		for item in eligibleItems {
			let uuidString = item.uuid.uuidString
			let sourceForItem = Model.appStorageUrl.appendingPathComponent(uuidString)
			let destinationForItem = tempPath.appendingPathComponent(uuidString)
			try fm.copyAndReplaceItem(at: sourceForItem, to: destinationForItem)
			p.completedUnitCount += 1
		}

		fm.delegate = nil
		delegate = nil

		let data = try JSONEncoder().encode(eligibleItems)
		try data.write(to: tempPath.appendingPathComponent("items.json"))
		p.completedUnitCount += 1

		completion(tempPath, nil)
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	@discardableResult
	static func createZip(completion: @escaping (URL?, Error?)->Void) -> Progress {

		let dropsCopy = eligibleDropsForExport
		let itemCount = Int64(1 + dropsCopy.count)
		let p = Progress(totalUnitCount: itemCount)

		DispatchQueue.global(qos: .userInitiated).async {
			do {
				try createZipThread(dropsCopy: dropsCopy, progress: p, completion: completion)
			} catch {
				completion(nil, error)
			}
		}

		return p
	}

	static func createZipThread(dropsCopy: [ArchivedDropItem], progress p: Progress, completion: @escaping (URL?, Error?)->Void) throws {

		let tempPath = Model.temporaryDirectoryUrl.appendingPathComponent("Gladys.zip")

		let fm = FileManager.default
		if fm.fileExists(atPath: tempPath.path) {
			try fm.removeItem(at: tempPath)
		}

		p.completedUnitCount += 1

		if let archive = Archive(url: tempPath, accessMode: .create) {
			for item in dropsCopy {
				let dir = item.displayTitleOrUuid.filenameSafe

				if item.typeItems.count == 1 {
					let typeItem = item.typeItems.first!
					try addZipItem(typeItem, directory: nil, name: dir, in: archive)

				} else {
					for typeItem in item.typeItems {
						try addZipItem(typeItem, directory: dir, name: typeItem.typeDescription, in: archive)
					}
				}
				p.completedUnitCount += 1
			}
		}

		completion(tempPath, nil)
	}

	static private func addZipItem(_ typeItem: ArchivedDropItemType, directory: String?, name: String, in archive: Archive) throws {

		var bytes: Data?
		if typeItem.isWebURL, let url = typeItem.encodedUrl, let data = url.urlFileContent {
			bytes = data

		} else if typeItem.classWasWrapped {
			bytes = typeItem.dataForWrappedItem ?? typeItem.bytes
		}
		if let B = bytes ?? typeItem.bytes {
			let timmedName = typeItem.prepareFilename(name: name, directory: directory)
			try archive.addEntry(with: timmedName, type: .file, uncompressedSize: UInt32(B.count)) { pos, size -> Data in
				return B[pos ..< pos+size]
			}
		}
	}
}
