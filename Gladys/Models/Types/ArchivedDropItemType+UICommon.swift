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
#if os(iOS)
import MobileCoreServices
#endif

extension ArchivedDropItemType {

	var dataExists: Bool {
		return FileManager.default.fileExists(atPath: bytesPath.path)
	}

	var sizeDescription: String? {
		return diskSizeFormatter.string(fromByteCount: sizeInBytes)
	}

	func deleteFromStorage() {
		CloudManager.markAsDeleted(uuid: uuid, cloudKitRecord: cloudKitRecord)
		let fm = FileManager.default
		if fm.fileExists(atPath: folderUrl.path) {
			log("Removing component storage at: \(folderUrl.path)")
			try? fm.removeItem(at: folderUrl)
		}
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

	var contentPriority: Int {

		if typeIdentifier == "com.apple.mapkit.map-item" { return 140 }

		if typeConforms(to: kUTTypeVCard) { return 120 }

		if isURL {
			if representedClass == .url { return 100 }
			if isWebURL { return 80 }
			return 60
		}

		if typeConforms(to: kUTTypeImage) { return 40 }

		if typeConforms(to: kUTTypeText) { return 20 }

		return 0
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

	var itemProviderForSharing: NSItemProvider {
		let p = NSItemProvider()
		#if os(iOS)
		p.suggestedName = oneTitle
		#endif
		registerForSharing(with: p)
		return p
	}

	func registerForSharing(with provider: NSItemProvider) {
		if let w = objectForShare as? NSItemProviderWriting {
			provider.registerObject(w, visibility: .all)
		} else {
			provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion -> Progress? in
				let p = Progress(totalUnitCount: 1)
				p.completedUnitCount = 1
				DispatchQueue.global(qos: .userInitiated).async {
					completion(self.dataForWrappedItem ?? self.bytes, nil)
				}
				return p
			}
		}
	}
}
