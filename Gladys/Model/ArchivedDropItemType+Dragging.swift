
import UIKit
import MapKit
import Contacts

extension ArchivedDropItemType {

	private var objCType: AnyClass? {
		guard let classType = classType else { return nil }
		switch classType {
		case .NSData: return NSData.self
		case .NSString: return NSString.self
		case .NSAttributedString: return NSAttributedString.self
		case .UIColor: return UIColor.self
		case .UIImage: return UIImage.self
		case .MKMapItem: return MKMapItem.self
		case .NSURL: return NSURL.self
		case .NSArray: return NSArray.self
		case .NSDictionary: return NSDictionary.self
		}
	}

	private func decodedObject(for classType: ClassType) -> NSSecureCoding? {
		switch classType {
		case .NSString:
			return decode(NSString.self)
		case .NSAttributedString:
			return decode(NSAttributedString.self)
		case .UIImage:
			return decode(UIImage.self)
		case .UIColor:
			return decode(UIColor.self)
		case .NSData:
			return decode(NSData.self)
		case .MKMapItem:
			return decode(MKMapItem.self)
		case .NSArray:
			return decode(NSArray.self)
		case .NSDictionary:
			return decode(NSDictionary.self)
		case .NSURL:
			return encodedUrl
		}
	}

	var dragItem: UIDragItem {

		let p = NSItemProvider()
		p.suggestedName = oneTitle
		register(with: p)

		let i = UIDragItem(itemProvider: p)
		i.localObject = ["local_object": self]
		return i
	}

	func register(with provider: NSItemProvider) {

		if let classType = classType, let myClass = objCType as? NSItemProviderWriting.Type {
			provider.registerObject(ofClass: myClass, visibility: .all) { (completion) -> Progress? in
				let decoded = self.decodedObject(for: classType) as? NSItemProviderWriting
				if let decoded = decoded {
					log("Responding with object type: \(type(of: decoded))")
				} else {
					log("Responding with nil object")
				}
				completion(decoded, nil)
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

				let deliveredClassType: ClassType
				if let requestedClassType = requestedClassType {
					deliveredClassType = ClassType(rawValue: NSStringFromClass(requestedClassType)) ?? .NSData
				} else if let classType = self.classType {
					deliveredClassType = classType
				} else {
					deliveredClassType = .NSData
				}

				log("Requested item type: \(requestedClassType), I have \(self.classType?.rawValue ?? "<unknown>"), will deliver: \(deliveredClassType.rawValue)")

				if let item = self.decodedObject(for: deliveredClassType) {
					log("Responding with item \(item)")
					completion(item, nil)
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
		guard let classType = classType else { return (nil, 0) }

		switch classType {
		case .MKMapItem: return (decode(MKMapItem.self), 30)
		case .UIColor: return (decode(UIColor.self), 10)
		default: return (nil, 0)
		}
	}

	var itemForShare: (Any?, Int) {

		if typeIdentifier == "public.vcard", let bytes = bytes, let contact = (try? CNContactVCardSerialization.contacts(with: bytes))?.first {
			return (contact, 12)
		}

		if typeIdentifier == "com.apple.mapkit.map-item", let item = decode(MKMapItem.self) {
			return (item, 15)
		}

		if let url = encodedUrl {

			if classType == .NSURL {
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
