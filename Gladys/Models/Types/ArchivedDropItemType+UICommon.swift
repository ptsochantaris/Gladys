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

			if representedClass == "URL" {
				return (url, 10)
			}

			if typeIdentifier == "public.url" {
				return (url, 5)
			}

			return (url, 3)
		}

		return (bytes, 0)
	}

	private func truncate(string: String, limit: Int) -> String {
		if string.count > limit {
			let s = string.startIndex
			let e = string.index(string.startIndex, offsetBy: limit)
			return String(string[s..<e])
		}
		return string
	}

	func prepareFilename(name: String, directory: String?) -> String {
		var name = name
		if let ext = fileExtension {
			name = truncate(string: name, limit: 255 - (ext.count+1)) + "." + ext
		} else {
			name = truncate(string: name, limit: 255)
		}

		if let directory = directory {
			let directory = truncate(string: directory, limit: 255)
			name = directory + "/" + name
		}

		// for now, remove in a few weeks
		return name.replacingOccurrences(of: "\0", with: "")
	}
}
