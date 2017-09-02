
import UIKit
import MapKit
import Contacts

extension ArchivedDropItemType {

	var dragItem: UIDragItem {

		let p = NSItemProvider()
		p.suggestedName = oneTitle
		registerForDrag(with: p)

		let i = UIDragItem(itemProvider: p)
		i.localObject = self
		return i
	}

	func registerForDrag(with provider: NSItemProvider) {

		guard let bytes = bytes else { return }

		if let classType = NSClassFromString(representedClass) as? NSItemProviderWriting.Type {
			provider.registerObject(ofClass: classType, visibility: .all) { (completion) -> Progress? in
				let decoded = self.decode()
				log("Responding with object type: \(type(of: decoded))")
				completion(decoded as? NSItemProviderWriting, nil)
				return nil
			}
		}

		provider.registerFileRepresentation(forTypeIdentifier: typeIdentifier, fileOptions: [], visibility: .all) { (completion) -> Progress? in
			let decoded = self.targetFileUrl
			log("Responding with file url: \(decoded.absoluteString)")
			completion(decoded, false, nil)
			return nil
		}

		provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { (completion) -> Progress? in
			log("Responding with data block")
			completion(self.bytesForDragging, nil)
			return nil
		}

		if !hasLocalFiles {

			provider.registerItem(forTypeIdentifier: typeIdentifier) { completion, requestedClassType, options in

				log("Requested item type: \(requestedClassType)")

				if let item = self.encodedUrl ?? self.decode(), let i = item as? NSSecureCoding {
					log("Delivering item type \(type(of: i))")
					completion(i, nil)
				} else {
					log("Responding with raw data")
					completion(bytes as NSData, nil)
				}
			}
		}
	}

	var dataExists: Bool {
		return FileManager.default.fileExists(atPath: bytesPath.path)
	}

	var backgroundInfoObject: (Any?, Int) {
		switch representedClass {
		case "MKMapItem": return (decode() as? MKMapItem, 30)
		case "UIColor": return (decode() as? UIColor, 10)
		default: return (nil, 0)
		}
	}

	var itemForShare: (Any?, Int) {

		if typeIdentifier == "public.vcard", let bytes = bytes, let contact = (try? CNContactVCardSerialization.contacts(with: bytes))?.first {
			return (contact, 12)
		}

		if typeIdentifier == "com.apple.mapkit.map-item", let item = decode() as? MKMapItem {
			return (item, 15)
		}

		if let url = encodedUrl {

			if representedClass == "NSURL" {
				return (url, 10)
			}

			if typeIdentifier == "public.url" {
				return (url, 5)
			}

			return (url, 3)
		}

		return (nil, 0)
	}
}
