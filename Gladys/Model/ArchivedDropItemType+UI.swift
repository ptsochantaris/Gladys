
import UIKit
import MapKit
import Contacts

extension ArchivedDropItemType {

	var dragItem: UIDragItem {

		let p = NSItemProvider()
		p.suggestedName = oneTitle
		registerForDrag(with: p)

		let i = UIDragItem(itemProvider: p)
		i.localObject = ["local_object": self]
		return i
	}

	func registerForDrag(with provider: NSItemProvider) {
		if classWasWrapped {
			registerWrapped(with: provider)
		} else {
			register(with: provider)
		}
	}

	private func registerWrapped(with provider: NSItemProvider) {

		if let classType = NSClassFromString(representedClass) as? NSItemProviderWriting.Type {
			provider.registerObject(ofClass: classType, visibility: .all) { (completion) -> Progress? in
				let decoded = self.decode()
				log("Responding with object type: \(type(of: decoded))")
				completion(decoded as? NSItemProviderWriting, nil)
				return nil
			}
		}

		if hasLocalFiles {
			provider.registerFileRepresentation(forTypeIdentifier: typeIdentifier, fileOptions: [], visibility: .all) { (completion) -> Progress? in
				let decoded = self.encodedUrl as URL?
				log("Responding with file url: \(decoded?.absoluteString ?? "<nil>")")
				completion(decoded, false, nil)
				return nil
			}

		} else if let bytes = bytes {

			provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { (completion) -> Progress? in
				log("Responding with wrapped data block")
				completion(bytes, nil)
				return nil
			}

			provider.registerItem(forTypeIdentifier: typeIdentifier) { completion, requestedClassType, options in
				log("Requested item type: \(requestedClassType), will only respond with wrapped data block, same way we got it")
				completion(bytes as NSData, nil)
			}
		}
	}

	private func register(with provider: NSItemProvider) {

		if let classType = NSClassFromString(representedClass) as? NSItemProviderWriting.Type {
			provider.registerObject(ofClass: classType, visibility: .all) { (completion) -> Progress? in
				let decoded = self.decode()
				log("Responding with object type: \(type(of: decoded))")
				completion(decoded as? NSItemProviderWriting, nil)
				return nil
			}
		}

		if hasLocalFiles {
			provider.registerFileRepresentation(forTypeIdentifier: typeIdentifier, fileOptions: [], visibility: .all) { (completion) -> Progress? in
				let decoded = self.encodedUrl as URL?
				log("Responding with file url: \(decoded?.absoluteString ?? "<nil>")")
				completion(decoded, false, nil)
				return nil
			}

		} else if let bytes = bytes {

			provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { (completion) -> Progress? in
				log("Responding with data block")
				completion(bytes, nil)
				return nil
			}

			provider.registerItem(forTypeIdentifier: typeIdentifier) { completion, requestedClassType, options in

				log("Requested item type: \(requestedClassType)")

				if let item = self.encodedUrl ?? self.decode() {
					log("Delivering item type \(type(of: item))")
					completion(item as? NSSecureCoding, nil)
				} else {
					log("Could not decode local data, responding with NSData item")
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
