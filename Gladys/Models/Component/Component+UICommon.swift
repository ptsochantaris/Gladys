//
//  Component+UICommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Contacts
import MapKit
#if os(iOS)
import MobileCoreServices
#endif

extension Component {

	var dataExists: Bool {
		return FileManager.default.fileExists(atPath: bytesPath.path)
	}

	var sizeDescription: String? {
		return diskSizeFormatter.string(fromByteCount: sizeInBytes)
	}

	func deleteFromStorage() {
		CloudManager.markAsDeleted(recordName: uuid.uuidString, cloudKitRecord: cloudKitRecord)
		let fm = FileManager.default
		if fm.fileExists(atPath: folderUrl.path) {
			log("Removing component storage at: \(folderUrl.path)")
			try? fm.removeItem(at: folderUrl)
		}
		clearCacheData(for: uuid)
		removeIntents()
	}

	var objectForShare: Any? {

		if typeIdentifier == "com.apple.mapkit.map-item", let item = decode() as? MKMapItem {
			return item
		}

		if typeConforms(to: kUTTypeVCard), let bytes = bytes, let contact = (try? CNContactVCardSerialization.contacts(with: bytes))?.first {
			return contact
		}

		if let url = encodedUrl {
			return url
		}

		return decode()
	}

	func prepareFilename(name: String, directory: String?) -> String {
		var name = name

		if let ext = fileExtension {
			if ext == "jpeg", name.hasSuffix(".jpg") {
				name = String(name.dropLast(4))

			} else if ext == "mpeg", name.hasSuffix(".mpg") {
				name = String(name.dropLast(4))

			} else if ext == "html", name.hasSuffix(".htm") {
				name = String(name.dropLast(4))

			} else if name.hasSuffix("." + ext) {
				name = String(name.dropLast(ext.count + 1))
			}

			name = name.truncate(limit: 255 - (ext.count + 1)) + "." + ext
		} else {
			name = name.truncate(limit: 255)
		}

		if let directory = directory {
			name = directory.truncate(limit: 255) + "/" + name
		}

		// for now, remove in a few weeks
		return name.replacingOccurrences(of: "\0", with: "")
	}
}
