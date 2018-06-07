//
//  Model+Common.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
#if os(iOS)
import FileProvider
#endif

extension Model {
	static var drops = [ArchivedDropItem]()
	static var dataFileLastModified = Date.distantPast
	static var isStarted = false

	static let itemsDirectoryUrl: URL = {
		return appStorageUrl.appendingPathComponent("items", isDirectory: true)
	}()

	static let temporaryDirectoryUrl: URL = {
		let url = appStorageUrl.appendingPathComponent("temporary", isDirectory: true)
		let fm = FileManager.default
		if fm.fileExists(atPath: url.path) {
			try? fm.removeItem(at: url)
		}
		try! fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		return url
	}()

	static func item(uuid: String) -> ArchivedDropItem? {
		let uuidData = UUID(uuidString: uuid)
		return drops.first { $0.uuid == uuidData }
	}

	static func item(uuid: UUID) -> ArchivedDropItem? {
		return drops.first { $0.uuid == uuid }
	}

	static func item(shareId: String) -> ArchivedDropItem? {
		return drops.first { $0.cloudKitShareRecord?.recordID.recordName == shareId }
	}

	static func typeItem(uuid: String) -> ArchivedDropItemType? {
		let uuidData = UUID(uuidString: uuid)
		return drops.compactMap { $0.typeItems.first { $0.uuid == uuidData } }.first
	}

	static func modificationDate(for url: URL) -> Date? {
		return (try? FileManager.default.attributesOfItem(atPath: url.path))?[FileAttributeKey.modificationDate] as? Date
	}

	static let appStorageUrl: URL = {
		#if MAC
			return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)!
		#elseif MAINAPP || FILEPROVIDER
			return NSFileProviderManager.default.documentStorageURL
		#else
			return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)!.appendingPathComponent("File Provider Storage")
		#endif
	}()
}
