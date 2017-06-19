
import UIKit
import MapKit
import Contacts

final class ArchivedDropItemType: Codable {

	private enum CodingKeys : String, CodingKey {
		case typeIdentifier
		case classType
		case uuid
		case allLoadedWell
		case parentUuid
		case accessoryTitle
	}

	func encode(to encoder: Encoder) throws {
		var v = encoder.container(keyedBy: CodingKeys.self)
		try v.encode(typeIdentifier, forKey: .typeIdentifier)
		try v.encodeIfPresent(classType?.rawValue, forKey: .classType)
		try v.encode(uuid, forKey: .uuid)
		try v.encode(allLoadedWell, forKey: .allLoadedWell)
		try v.encode(parentUuid, forKey: .parentUuid)
		try v.encodeIfPresent(accessoryTitle, forKey: .accessoryTitle)
	}

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		typeIdentifier = try v.decode(String.self, forKey: .typeIdentifier)
		if let typeValue = try v.decodeIfPresent(String.self, forKey: .classType) {
			classType = ClassType(rawValue: typeValue)
		}
		uuid = try v.decode(UUID.self, forKey: .uuid)
		parentUuid = try v.decode(UUID.self, forKey: .parentUuid)
		allLoadedWell = try v.decode(Bool.self, forKey: .allLoadedWell)
		accessoryTitle = try v.decodeIfPresent(String.self, forKey: .accessoryTitle)

		// Completing setup
		patchLocalUrl()
		displayTitle = updatedDisplayTitle()
		displayIcon = updatedDisplayIcon()
	}

	private var bytes: Data? {
		set {
			NSLog("setting bytes")
			let byteLocation = folderUrl.appendingPathComponent("blob", isDirectory: false)
			if newValue == nil {
				let f = FileManager.default
				if f.fileExists(atPath: byteLocation.path) {
					try! f.removeItem(at: byteLocation)
				}
			} else {
				try! newValue?.write(to: byteLocation, options: [.atomic])
			}
		}
		get {
			let byteLocation = folderUrl.appendingPathComponent("blob", isDirectory: false)
			if FileManager.default.fileExists(atPath: byteLocation.path) {
				return try! Data(contentsOf: byteLocation, options: [])
			} else {
				return nil
			}
		}
	}

	private let typeIdentifier: String
	private var classType: ClassType?
	private let uuid: UUID
	private let parentUuid: UUID
	var accessoryTitle: String?

	// transient / ui
	private weak var delegate: LoadCompletionDelegate?
	private var loadCount = 0
	private var allLoadedWell = true

	private enum ClassType: String {
		case NSString, NSAttributedString, UIColor, UIImage, NSData, MKMapItem, NSURL
	}

	private func decode<T>(_ type: T.Type) -> T? where T: NSSecureCoding {
		guard let bytes = bytes else { return nil }

		let u = NSKeyedUnarchiver(forReadingWith: bytes)
		let className = String(describing: type)
		return u.decodeObject(of: [NSClassFromString(className)!], forKey: className) as? T
	}

	var backgroundInfoObject: (Any?, Int) {
		guard let classType = classType else { return (nil, 0) }

		switch classType {

		case .MKMapItem: return (decode(MKMapItem.self), 30)

		case .UIColor: return (decode(UIColor.self), 10)

		default: return (nil, 0)
		}
	}

	private func patchLocalUrl() {

		if let myDataIsAUrl = decode(NSURL.self) {

			if myDataIsAUrl.scheme == "file", let s = myDataIsAUrl.absoluteString, let classType = classType {
				let myPath = "\(parentUuid)/\(uuid)/"
				if let indexUpToMyPath = s.range(of: myPath)?.lowerBound {
					let keep = s.substring(from: indexUpToMyPath)
					let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
					let correctUrl = docs.appendingPathComponent(keep) as NSURL
					setBytes(object: correctUrl, type: classType)
				}
			}
		}
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
					provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
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
					self.fetchWebTitle(for: item) { [weak self] title in
						self?.accessoryTitle = title ?? self?.accessoryTitle
						self?.signalDone()
					}
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

	private func fetchWebTitle(for url: URL, testing: Bool = true, completion: @escaping (String?)->Void) {

		// in thread!!

		if testing {

			NSLog("Investigating possible HTML title from this URL")

			var request = URLRequest(url: url)
			request.addValue("text/html", forHTTPHeaderField: "Accept")
			request.httpMethod = "HEAD"
			let headFetch = URLSession.shared.dataTask(with: request) { data, response, error in
				if let response = response as? HTTPURLResponse {
					if let type = response.allHeaderFields["Content-Type"] as? String, type.hasPrefix("text/html") {
						NSLog("Content for this is HTML, will try to fetch title")
						self.fetchWebTitle(for: url, testing: false, completion: completion)
					} else {
						NSLog("Content for this isn't HTML, never mind")
						completion(nil)
					}
				}
			}
			headFetch.resume()

		} else {
			let fetch = URLSession.shared.dataTask(with: url) { data, response, error in
				if let data = data,
					let html = String(data: data, encoding: .utf8),
					let titleStart = html.range(of: "<title>")?.upperBound {
					let sub = html.substring(from: titleStart)
					if let titleEnd = sub.range(of: "</title>")?.lowerBound {
						let title = sub.substring(to: titleEnd)
						DispatchQueue.main.async {
							completion(title)
							return
						}
					}
				}
				completion(nil)
			}
			fetch.resume()
		}
	}

	// TODO: MEMORY LEAK BIGTIME

	private func signalDone() {
		displayIcon = updatedDisplayIcon()
		displayTitle = updatedDisplayTitle()
		DispatchQueue.main.async {
			self.delegate?.loadCompleted(success: self.allLoadedWell)
		}
	}

	lazy var folderUrl: URL = {
		let f = FileManager.default
		let docs = f.urls(for: .documentDirectory, in: .userDomainMask).first!
		let url = docs.appendingPathComponent(self.parentUuid.uuidString).appendingPathComponent(self.uuid.uuidString)
		if !f.fileExists(atPath: url.path) {
			try! f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}
		return url
	}()

	private func copyLocal(_ url: URL) -> URL {

		let newUrl = folderUrl.appendingPathComponent(url.lastPathComponent)
		let f = FileManager.default
		if f.fileExists(atPath: newUrl.path) {
			try! f.removeItem(at: newUrl)
		}
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

			NSLog("requested type: \(requestedClassType), our type: \(classType.rawValue)")

			let item: NSSecureCoding?
			switch classType {
			case .NSString:
				item = self.decode(NSString.self)
			case .NSAttributedString:
				item = self.decode(NSAttributedString.self)
			case .UIImage:
				item = self.decode(UIImage.self)
			case .UIColor:
				item = self.decode(UIColor.self)
			case .NSData:
				item = self.decode(NSData.self)
			case .MKMapItem:
				item = self.decode(MKMapItem.self)
			case .NSURL:
				item = self.decode(NSURL.self)
			}

			let finalName = String(describing: item)
			NSLog("Responding with \(finalName)")
			completion(item ?? (bytes as NSData), nil)

		} else {
			completion(nil, nil)
		}
	}

    lazy var displayIcon: (UIImage?, Int, UIViewContentMode) = { return self.updatedDisplayIcon() }()
	private func updatedDisplayIcon() -> (UIImage?, Int, UIViewContentMode){
		if let data = self.bytes {

			if classType == .UIImage {
				if let a = decode(UIImage.self) {
					return (a, 15, .scaleAspectFill)
				}
			}

			if typeIdentifier == "public.png" || typeIdentifier == "public.jpeg" {
				if classType == .NSURL {
					if let url = decode(NSURL.self), let path = url.path, let image = UIImage(contentsOfFile: path) {
						return (image, 10, .scaleAspectFill)
					}
				} else if classType == .NSData {
					if let image = UIImage(data: data) {
						return (image, 10, .scaleAspectFill)
					}
				}
			}

			if typeIdentifier == "public.vcard" {
				if let contacts = try? CNContactVCardSerialization.contacts(with: data),
					let person = contacts.first,
					let imageData = person.imageData,
					let img = UIImage(data: imageData) {

					return (img, 9, .scaleAspectFill)
				} else {
					return (#imageLiteral(resourceName: "iconPerson"), 5, .center)
				}
			}

			if typeIdentifier == "com.apple.mapkit.map-item" {
				return (#imageLiteral(resourceName: "iconMap"), 5, .center)
			}

			if classType == .NSString || classType == .NSAttributedString || typeIdentifier.hasSuffix("-plain-text") {
				return (#imageLiteral(resourceName: "iconText"), 5, .center)
			}

			if classType == .NSURL {
				if typeIdentifier.hasPrefix("com.apple.DocumentManager.uti.FPItem") {
					if typeIdentifier.hasSuffix("Location") {
						return(#imageLiteral(resourceName: "iconFolder"), 5, .center)
					}
					return (#imageLiteral(resourceName: "iconBlock"), 5, .center)
				} else {
					return(#imageLiteral(resourceName: "iconLink"), 5, .center)
				}
			}
		}
		return (#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
	}

	lazy var displayTitle: (String?, Int, NSTextAlignment) = { self.updatedDisplayTitle() }()
	private func updatedDisplayTitle() -> (String?, Int, NSTextAlignment) {

		if classType == .NSString {
			if let res = decode(NSString.self) as String? {
				return (res, 10, preferredAlignment(for: res))
			}
		} else if classType == .NSAttributedString {
			let a = decode(NSAttributedString.self)
			if let res = a?.string {
				return (res, 7, preferredAlignment(for: res))
			}
		} else if classType == .NSURL {
			if let url = decode(NSURL.self), url.scheme != "file", let res = url.absoluteString {
				return (res, 6, .center)
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
					return (name, 9, .center)
				}

			} else if typeIdentifier == "public.utf8-plain-text" {
				let s = String(data: data, encoding: .utf8)
				return (s, 9, preferredAlignment(for: s))
			} else if typeIdentifier == "public.utf16-plain-text" {
				let s = String(data: data, encoding: .utf16)
				return (s, 8, preferredAlignment(for: s))
			}
		}

		return (nil, 0, .center)
	}

	private func preferredAlignment(for string: String?) -> NSTextAlignment {
		if let string = string, string.characters.count > 200 {
			return .justified
		}
		return .center
	}

	var itemForShare: (Any?, Int) {

		if typeIdentifier == "public.vcard", let bytes = bytes, let contact = try? CNContactVCardSerialization.contacts(with: bytes) {
			return (contact, 12)
		}

		if typeIdentifier == "com.apple.mapkit.map-item", let item = decode(MKMapItem.self) {
			return (item, 15)
		}

		if let url = decode(NSURL.self) as URL? {

			if classType == .NSURL {
				return (url, 10)
			}

			if typeIdentifier == "public.url" {
				return (url, 5)
			}

			return (url, 1)
		}

		return (nil, 0)
	}
}

