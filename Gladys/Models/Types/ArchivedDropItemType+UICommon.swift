//
//  ArchivedDropItemType+UICommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Contacts
import MapKit

extension ArchivedDropItemType {

	var dataExists: Bool {
		return FileManager.default.fileExists(atPath: bytesPath.path)
	}

	var sizeDescription: String? {
		return diskSizeFormatter.string(fromByteCount: sizeInBytes)
	}

	func deleteFromStorage() {
		let fm = FileManager.default
		if fm.fileExists(atPath: folderUrl.path) {
			log("Removing component storage at: \(folderUrl.path)")
			try? fm.removeItem(at: folderUrl)
		}
		CloudManager.markAsDeleted(uuid: uuid)
	}

	var itemForShare: (Any?, Int) {

		if typeIdentifier == "public.vcard", let bytes = bytes, let contact = (try? CNContactVCardSerialization.contacts(with: bytes))?.first {
			return (contact, 12)
		}

		if typeIdentifier == "com.apple.mapkit.map-item", let item = decode() as? MKMapItem {
			return (item, 15)
		}

		if let url = encodedUrl {

			if representedClass == .url {
				return (url, 10)
			}

			if isWebURL {
				return (url, 5)
			}

			return (url, 3)
		}

		return (bytes, 0)
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
