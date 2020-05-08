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

	private static func bringInItem(_ item: ArchivedItem, from url: URL, using fm: FileManager, moveItem: Bool) throws -> Bool {

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

	static func importArchive(from url: URL, removingOriginal: Bool) throws {
		let fm = FileManager.default
		defer {
			if removingOriginal {
				try? fm.removeItem(at: url)
			}
			save()
		}

        let finalPath = url.appendingPathComponent("items.json")
        guard let data = Data.forceMemoryMapped(contentsOf: finalPath) else {
            throw NSError(domain: GladysErrorDomain, code: 96, userInfo: [NSLocalizedDescriptionKey: "Could not read imported archive"])
        }
		let itemsInPackage = try loadDecoder.decode(Array<ArchivedItem>.self, from: data)

		for item in itemsInPackage.reversed() {
			if let i = drops.firstIndexOfItem(with: item.uuid) {
				if drops.all[i].updatedAt >= item.updatedAt || drops.all[i].shareMode != .none {
					continue
				}
				if try bringInItem(item, from: url, using: fm, moveItem: removingOriginal) {
                    drops.replaceItem(at: i, with: item)
				}
			} else {
				if try bringInItem(item, from: url, using: fm, moveItem: removingOriginal) {
					drops.insert(item, at: 0)
				}
			}
		}
	}

	private class FileManagerFilter: NSObject, FileManagerDelegate {
		func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool {
			guard let lastComponent = srcURL.pathComponents.last else { return false }
			return !(lastComponent == "shared-blob" || lastComponent == "ck-record" || lastComponent == "ck-share")
		}
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	@discardableResult
    static func createArchive(using filter: ModelFilterContext, completion: @escaping (URL?, Error?) -> Void) -> Progress {
        let eligibleItems: ContiguousArray = filter.eligibleDropsForExport.filter { !$0.isImportedShare }
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

	static private func createArchiveThread(progress p: Progress, eligibleItems: ContiguousArray<ArchivedItem>, completion: @escaping (URL?, Error?) -> Void) throws {
		let fm = FileManager()
		let tempPath = Model.temporaryDirectoryUrl.appendingPathComponent("Gladys Archive.gladysArchive")
        let path = tempPath.path
		if fm.fileExists(atPath: path) {
			try fm.removeItem(atPath: path)
		}

		let delegate = FileManagerFilter()
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

		let data = try saveEncoder.encode(eligibleItems)
        let finalPath = tempPath.appendingPathComponent("items.json")
		try data.write(to: finalPath)
		p.completedUnitCount += 1

		completion(tempPath, nil)
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	@discardableResult
    static func createZip(using filter: ModelFilterContext, completion: @escaping (URL?, Error?) -> Void) -> Progress {

        let dropsCopy = filter.eligibleDropsForExport
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

	static func createZipThread(dropsCopy: ContiguousArray<ArchivedItem>, progress p: Progress, completion: @escaping (URL?, Error?) -> Void) throws {

		let tempPath = Model.temporaryDirectoryUrl.appendingPathComponent("Gladys.zip")

		let fm = FileManager.default
        let path = tempPath.path
		if fm.fileExists(atPath: path) {
			try fm.removeItem(atPath: path)
		}

		p.completedUnitCount += 1

		if let archive = Archive(url: tempPath, accessMode: .create) {
			for item in dropsCopy {
				let dir = item.displayTitleOrUuid.filenameSafe

				if item.components.count == 1, let typeItem = item.components.first {
					try addZipItem(typeItem, directory: nil, name: dir, in: archive)

				} else {
					for typeItem in item.components {
						try addZipItem(typeItem, directory: dir, name: typeItem.typeDescription, in: archive)
					}
				}
				p.completedUnitCount += 1
			}
		}

		completion(tempPath, nil)
	}

	static private func addZipItem(_ typeItem: Component, directory: String?, name: String, in archive: Archive) throws {

		var bytes: Data?
		if typeItem.isWebURL, let url = typeItem.encodedUrl, let data = url.urlFileContent {
			bytes = data

		} else if typeItem.classWasWrapped {
			bytes = typeItem.dataForDropping ?? typeItem.bytes
		}
		if let B = bytes ?? typeItem.bytes {
			let timmedName = typeItem.prepareFilename(name: name, directory: directory)
			try archive.addEntry(with: timmedName, type: .file, uncompressedSize: UInt32(B.count)) { pos, size -> Data in
				return B[pos ..< pos+size]
			}
		}
	}

	static func trimTemporaryDirectory() {
		do {
			let fm = FileManager.default
			let contents = try fm.contentsOfDirectory(atPath: temporaryDirectoryUrl.path)
			let now = Date()
			for name in contents {
                let url = temporaryDirectoryUrl.appendingPathComponent(name)
                let path = url.path
                if (Component.PreviewItem.previewUrls[url] ?? 0) > 0 {
                    log("Temporary directory entry is in use, will skip check: \(path)")
                    continue
                }
				let attributes = try fm.attributesOfItem(atPath: path)
				if let accessDate = (attributes[FileAttributeKey.modificationDate] ?? attributes[FileAttributeKey.creationDate]) as? Date, now.timeIntervalSince(accessDate) > 3600 {
                    log("Temporary directory entry is old, will trim: \(path)")
                    try? fm.removeItem(atPath: path)
				}
			}
		} catch {
			log("Error trimming temporary directory: \(error.localizedDescription)")
		}
	}
}
