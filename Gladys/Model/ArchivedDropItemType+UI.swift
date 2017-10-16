
import UIKit
import MapKit
import Contacts

extension ArchivedDropItemType {

	var dragItem: UIDragItem {

		let p = NSItemProvider()
		p.suggestedName = oneTitle
		register(with: p)

		let i = UIDragItem(itemProvider: p)
		i.localObject = self
		return i
	}

	func register(with provider: NSItemProvider) {
		provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion -> Progress? in
			let p = Progress(totalUnitCount: 1)
			p.completedUnitCount = 1
			DispatchQueue.global(qos: .userInitiated).async {
				log("Responding with data block")
				completion(self.bytes, nil)
			}
			return p
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

			if representedClass == "URL" {
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
