
import UIKit
import MapKit
import Contacts

final class ArchivedDropItemType: Codable {

	private enum CodingKeys : String, CodingKey {
		case typeIdentifier
		case classType
		case bytes
		case uuid
		case allLoadedWell
		case parentUuid
	}

	func encode(to encoder: Encoder) throws {
		var v = encoder.container(keyedBy: CodingKeys.self)
		try v.encode(typeIdentifier, forKey: .typeIdentifier)
		try v.encodeIfPresent(classType?.rawValue, forKey: .classType)
		try v.encodeIfPresent(bytes, forKey: .bytes)
		try v.encode(uuid, forKey: .uuid)
		try v.encode(allLoadedWell, forKey: .allLoadedWell)
		try v.encode(parentUuid, forKey: .parentUuid)
	}

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		typeIdentifier = try v.decode(String.self, forKey: .typeIdentifier)
		if let typeValue = try v.decodeIfPresent(String.self, forKey: .classType) {
			classType = ClassType(rawValue: typeValue)
		}
		bytes = try v.decode(Data.self, forKey: .bytes)
		uuid = try v.decode(UUID.self, forKey: .uuid)
		parentUuid = try v.decode(UUID.self, forKey: .parentUuid)
		allLoadedWell = try v.decode(Bool.self, forKey: .allLoadedWell)
	}

	private let typeIdentifier: String
	private var classType: ClassType?
	private var bytes: Data?
	private let uuid: UUID
	private let parentUuid: UUID

	// transient / ui
	private weak var delegate: LoadCompletionDelegate?
	private var loadCount = 0
	private var allLoadedWell = true

	private enum ClassType: String {
		case NSString, NSAttributedString, UIColor, UIImage, NSData, MKMapItem, NSURL
	}

	private func decode(_ type: ClassType) -> Any? {
		guard let bytes = bytes else { return nil }
		let u = NSKeyedUnarchiver(forReadingWith: bytes)
		let className = type.rawValue
		return u.decodeObject(of: [NSClassFromString(className)!], forKey: className)
	}

	var backgroundInfoObject: (Any?, Int) {
		guard let classType = classType else { return (nil, 0) }

		switch classType {

		case .MKMapItem: return (decode(.MKMapItem), 30)

		case .UIColor: return (decode(.UIColor), 10)

		case .NSURL:
			let url = decodedUrl
			if url?.scheme != "file" {
				return  (url, 20)
			}
			fallthrough

		default: return (nil, 0)
		}
	}

	private var decodedUrl: NSURL? {
		if let url = decode(.NSURL) as? NSURL {

			if url.scheme == "file", let s = url.absoluteString {
				let myPath = "\(parentUuid)/\(uuid)/"
				if let indexUpToMyPath = s.range(of: myPath)?.lowerBound {
					let keep = s.substring(from: indexUpToMyPath)
					let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
					return docs.appendingPathComponent(keep) as NSURL
				}
			}

			return url
		}
		return nil
	}

	func register(with provider: NSItemProvider) {
		provider.registerItem(forTypeIdentifier: typeIdentifier, loadHandler: loadHandler)
	}

	private func setBytes(object: Any, type: ClassType) {
		let d = NSMutableData()
		let k = NSKeyedArchiver(forWritingWith: d)
		k.encode(object, forKey: type.rawValue)
		k.finishEncoding()
		bytes = d as Data
		classType = type
	}

	init(provider: NSItemProvider, typeIdentifier: String, parentUuid: UUID, delegate: LoadCompletionDelegate) {

		self.uuid = UUID()
		self.typeIdentifier = typeIdentifier
		self.delegate = delegate
		self.parentUuid = parentUuid

		provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
			if let item = item {
				let receivedTypeString = type(of: item)
				NSLog("name: [\(provider.suggestedName ?? "")] type: [\(typeIdentifier)] class: [\(receivedTypeString)]")
			}

			if let item = item as? NSString {
				NSLog("      received string: \(item)")
				self.setBytes(object: item, type: .NSString)
				self.signalDone()

			} else if let item = item as? NSAttributedString {
				NSLog("      received attributed string: \(item)")
				self.setBytes(object: item, type: .NSAttributedString)
				self.signalDone()

			} else if let item = item as? UIColor {
				NSLog("      received color: \(item)")
				self.setBytes(object: item, type: .UIColor)
				self.signalDone()

			} else if let item = item as? UIImage {
				NSLog("      received image: \(item)")
				self.setBytes(object: item, type: .UIImage)
				self.signalDone()

			} else if let item = item as? Data {
				NSLog("      received data: \(item)")
				self.classType = .NSData
				self.bytes = item
				self.signalDone()

			} else if let item = item as? MKMapItem {
				NSLog("      received map item: \(item)")
				self.setBytes(object: item, type: .MKMapItem)
				self.signalDone()

			} else if let item = item as? URL {
				if item.scheme == "file" {
					NSLog("      will duplicate item at local url: \(item)")
					provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isLocal, error in
						if let url = url {
							let localUrl = self.copyLocal(url)
							NSLog("      received to local url: \(localUrl)")
							self.setBytes(object: localUrl, type: .NSURL)
							self.signalDone()

						} else if let error = error {
							NSLog("Error fetching local url file representation: \(error.localizedDescription)")
							self.allLoadedWell = false
							self.signalDone()
						}
					}
				} else {
					NSLog("      received remote url: \(item)")
					self.setBytes(object: item, type: .NSURL)
					self.signalDone()
				}

			} else if let error = error {
				NSLog("      error receiving item: \(error.localizedDescription)")
				self.allLoadedWell = false
				self.signalDone()


			} else {
				NSLog("      unknown class")
				self.allLoadedWell = false
				self.signalDone()
				// TODO: generate analyitics report to record what type was received and what UTI
			}
		}
	}

	private func signalDone() {
		DispatchQueue.main.async {
			self.delegate?.loadCompleted(success: self.allLoadedWell)
		}
	}

	private func copyLocal(_ url: URL) -> URL {

		let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
		let folderUrl = docs.appendingPathComponent(self.parentUuid.uuidString).appendingPathComponent(self.uuid.uuidString)

		let f = FileManager.default
		if f.fileExists(atPath: folderUrl.path) {
			try! f.removeItem(at: folderUrl)
		}
		try! f.createDirectory(at: folderUrl, withIntermediateDirectories: true, attributes: nil)
		let newUrl = folderUrl.appendingPathComponent(url.lastPathComponent)
		try! f.copyItem(at: url, to: newUrl)
		return newUrl
	}

	private lazy var loadHandler: NSItemProvider.LoadHandler = { completion, requestedClassType, options in

		if let bytes = self.bytes, let classType = self.classType {

			if requestedClassType != nil {
				let requestedClassName = NSStringFromClass(requestedClassType)
				if requestedClassName == "NSData" {
					completion(bytes as NSData, nil)
					return
				}
			}

			let item = self.decode(classType) as? NSSecureCoding
			let finalName = String(describing: item)
			NSLog("Responding with \(finalName)")
			completion(item ?? (bytes as NSData), nil)

		} else {
			completion(nil, nil)
		}
	}

	var displayIcon: (UIImage?, Int, UIViewContentMode) {
		if let data = self.bytes {

			if classType == .UIImage {
				if let a = decode(.UIImage) as? UIImage {
					return (a, 15, .scaleAspectFill)
				}
			}

			if typeIdentifier == "public.png" || typeIdentifier == "public.jpeg" {
				if classType == .NSURL {
					if let url = decodedUrl, let path = url.path, let image = UIImage(contentsOfFile: path) {
						return (image, 10, .scaleAspectFill)
					}
				} else if classType == .NSData {
					if let image = UIImage(data: data) {
						return (image, 10, .scaleAspectFill)
					}
				}
			}

			if typeIdentifier == "public.vcard" {
				return (#imageLiteral(resourceName: "iconPerson"), 5, .center)
			}

			if typeIdentifier == "com.apple.mapkit.map-item" {
				return (#imageLiteral(resourceName: "iconMap"), 5, .center)
			}

			if classType == .NSString || classType == .NSAttributedString || typeIdentifier.hasSuffix("-plain-text") {
				return (#imageLiteral(resourceName: "iconText"), 5, .center)
			}

			if classType == .NSURL {
				if typeIdentifier == "com.apple.DocumentManager.uti.FPItem.File" {
					return (#imageLiteral(resourceName: "iconBlock"), 5, .center)
				} else if typeIdentifier == "com.apple.DocumentManager.uti.FPItem.Location" {
					return(#imageLiteral(resourceName: "iconFolder"), 5, .center)
				} else {
					return(#imageLiteral(resourceName: "iconLink"), 5, .center)
				}
			}
		}
		return (#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
	}

	var displayTitle: (String?, Int) {

		if classType == .NSString {
			if let res = decode(.NSString) as? String {
				return (res, 10)
			}
		} else if classType == .NSAttributedString {
			let a = decode(.NSAttributedString) as? NSAttributedString
			if let res = a?.string {
				return (res, 7)
			}
		} else if classType == .NSURL {
			if let url = decodedUrl, url.scheme != "file", let res = url.absoluteString {
				return (res, 6)
			}
		}

		if let data = self.bytes {
			if typeIdentifier == "public.vcard" {
				if let contacts = try? CNContactVCardSerialization.contacts(with: data), let person = contacts.first {
					var name = ""
					if !person.givenName.isEmpty { name += person.givenName }
					if !name.isEmpty && !person.familyName.isEmpty { name += " " }
					if !person.familyName.isEmpty { name += person.familyName }
					if !name.isEmpty && !person.organizationName.isEmpty { name += " - " }
					if !person.organizationName.isEmpty { name += person.organizationName }
					return (name, 9)
				}

			} else if typeIdentifier == "public.utf8-plain-text" {
				return (String(data: data, encoding: .utf8), 9)
			} else if typeIdentifier == "public.utf16-plain-text" {
				return (String(data: data, encoding: .utf16), 8)
			}
		}

		return (nil, 0)
	}
}

