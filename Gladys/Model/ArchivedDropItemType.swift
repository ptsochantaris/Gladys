
import UIKit
import MapKit
import Contacts
import Fuzi

final class ArchivedDropItemType: Codable {

	private enum CodingKeys : String, CodingKey {
		case typeIdentifier
		case classType
		case uuid
		case allLoadedWell
		case parentUuid
		case accessoryTitle
		case displayTitle
		case displayTitleAlignment
		case displayTitlePriority
		case displayIconPriority
		case displayIconContentMode
		case displayIconScale
	}

	func encode(to encoder: Encoder) throws {
		var v = encoder.container(keyedBy: CodingKeys.self)
		try v.encode(typeIdentifier, forKey: .typeIdentifier)
		try v.encodeIfPresent(classType?.rawValue, forKey: .classType)
		try v.encode(uuid, forKey: .uuid)
		try v.encode(allLoadedWell, forKey: .allLoadedWell)
		try v.encode(parentUuid, forKey: .parentUuid)
		try v.encodeIfPresent(accessoryTitle, forKey: .accessoryTitle)
		try v.encodeIfPresent(displayTitle, forKey: .displayTitle)
		try v.encode(displayTitleAlignment.rawValue, forKey: .displayTitleAlignment)
		try v.encode(displayTitlePriority, forKey: .displayTitlePriority)
		try v.encode(displayIconContentMode.rawValue, forKey: .displayIconContentMode)
		try v.encode(displayIconPriority, forKey: .displayIconPriority)
		try v.encode(displayIconScale, forKey: .displayIconScale)

		let imagePath = folderUrl.appendingPathComponent("thumbnail.png")
		if let displayIcon = displayIcon {
			try! UIImagePNGRepresentation(displayIcon)!.write(to: imagePath)
		} else if FileManager.default.fileExists(atPath: imagePath.path) {
			try! FileManager.default.removeItem(at: imagePath)
		}
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
		displayTitle = try v.decodeIfPresent(String.self, forKey: .displayTitle)
		displayTitlePriority = try v.decode(Int.self, forKey: .displayTitlePriority)
		displayIconPriority = try v.decode(Int.self, forKey: .displayIconPriority)
		displayIconScale = try v.decode(CGFloat.self, forKey: .displayIconScale)

		let a = try v.decode(Int.self, forKey: .displayTitleAlignment)
		displayTitleAlignment = NSTextAlignment(rawValue: a) ?? .center

		let m = try v.decode(Int.self, forKey: .displayIconContentMode)
		displayIconContentMode = ArchivedDropItemDisplayType(rawValue: m) ?? .center

		let imagePath = folderUrl.appendingPathComponent("thumbnail.png")
		if 	let cgDataProvider = CGDataProvider(url: imagePath as CFURL),
			let cgImage = CGImage(pngDataProviderSource: cgDataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
			displayIcon = UIImage(cgImage: cgImage, scale: displayIconScale, orientation: .up)
		}

		patchLocalUrl()
	}

	private func patchLocalUrl() {

		if let encodedURL = decode(NSURL.self), encodedURL.scheme == "file", let currentPath = encodedURL.path, let classType = classType {

			let myPath = "\(parentUuid)/\(uuid)/"
			if let indexUpToMyPath = currentPath.range(of: myPath)?.lowerBound {
				let keep = currentPath.substring(from: indexUpToMyPath)
				let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
				let correctUrl = docs.appendingPathComponent(keep) as NSURL
				if encodedURL != correctUrl {
					setBytes(object: correctUrl, type: classType)
				}
			}
		}
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
		case string, attributedString, color, image, data, mapItem, url
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

		case .mapItem: return (decode(MKMapItem.self), 30)

		case .color: return (decode(UIColor.self), 10)

		default: return (nil, 0)
		}
	}

	func register(with provider: NSItemProvider) {
		provider.registerItem(forTypeIdentifier: typeIdentifier) { completion, requestedClassType, options in

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
				case .string:
					item = self.decode(NSString.self)
				case .attributedString:
					item = self.decode(NSAttributedString.self)
				case .image:
					item = self.decode(UIImage.self)
				case .color:
					item = self.decode(UIColor.self)
				case .data:
					item = self.decode(NSData.self)
				case .mapItem:
					item = self.decode(MKMapItem.self)
				case .url:
					item = self.decode(NSURL.self)
				}

				let finalName = String(describing: item)
				NSLog("Responding with \(finalName)")
				completion(item ?? (bytes as NSData), nil)

			} else {
				completion(nil, nil)
			}
		}
	}

	private func setBytes(object: Any, type: ClassType) {
		let d = NSMutableData()
		let k = NSKeyedArchiver(forWritingWith: d)
		k.encode(object, forKey: type.rawValue)
		k.finishEncoding()
		bytes = d as Data
		classType = type
	}

	private func ingest(item: NSSecureCoding, from provider: NSItemProvider) { // in thread!

		if let item = item as? NSString {
			NSLog("      received string: \(item)")
			setTitleInfo(item as String, 10)
			setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)
			setBytes(object: item, type: .string)
			signalDone()

		} else if let item = item as? NSAttributedString {
			NSLog("      received attributed string: \(item)")
			setTitleInfo(item.string, 7)
			setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)
			setBytes(object: item, type: .attributedString)
			signalDone()

		} else if let item = item as? UIColor {
			NSLog("      received color: \(item)")
			setBytes(object: item, type: .color)
			signalDone()

		} else if let item = item as? UIImage {
			NSLog("      received image: \(item)")
			setDisplayIcon(item, 15, .fill)
			setBytes(object: item, type: .image)
			signalDone()

		} else if let item = item as? Data {
			NSLog("      received data: \(item)")
			classType = .data
			bytes = item

			if let image = UIImage(data: item) {
				setDisplayIcon(image, 10, .fill)
			}

			if typeIdentifier == "public.vcard" {
				if let contacts = try? CNContactVCardSerialization.contacts(with: item), let person = contacts.first {
					let name = [person.givenName, person.middleName, person.familyName].filter({ !$0.isEmpty }).joined(separator: " ")
					let job = [person.jobTitle, person.organizationName].filter({ !$0.isEmpty }).joined(separator: ", ")
					accessoryTitle = [name, job].filter({ !$0.isEmpty }).joined(separator: " - ")

					if let imageData = person.imageData, let img = UIImage(data: imageData) {
						setDisplayIcon(img, 9, .circle)
					} else {
						setDisplayIcon(#imageLiteral(resourceName: "iconPerson"), 5, .center)
					}
				}

			} else if typeIdentifier == "public.utf8-plain-text" {
				let s = String(data: item, encoding: .utf8)
				setTitleInfo(s, 9)
				setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)

			} else if typeIdentifier == "public.utf16-plain-text" {
				let s = String(data: item, encoding: .utf16)
				setTitleInfo(s, 8)
				setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)

			} else if typeIdentifier == "com.apple.mapkit.map-item" {
				setDisplayIcon (#imageLiteral(resourceName: "iconMap"), 5, .center)

			}

			signalDone()

		} else if let item = item as? MKMapItem {
			NSLog("      received map item: \(item)")
			setBytes(object: item, type: .mapItem)
			setDisplayIcon (#imageLiteral(resourceName: "iconMap"), 10, .center)
			signalDone()

		} else if let item = item as? URL {

			if typeIdentifier.hasPrefix("com.apple.DocumentManager.uti.FPItem") {
				if typeIdentifier.hasSuffix("Location") {
					setDisplayIcon(#imageLiteral(resourceName: "iconFolder"), 5, .center)
				} else {
					setDisplayIcon (#imageLiteral(resourceName: "iconBlock"), 5, .center)
				}
			} else {
				setDisplayIcon(#imageLiteral(resourceName: "iconLink"), 5, .center)
			}

			if item.scheme == "file" {
				NSLog("      will duplicate item at local path: \(item.path)")
				provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, wasLocal, error in
					self?.handleLocalFetch(url: url, error: error)
					self?.signalDone()
				}
			} else {
				NSLog("      received remote url: \(item.absoluteString)")
				setTitleInfo(item.absoluteString, 6)
				setBytes(object: item, type: .url)
				fetchWebPreview(for: item) { [weak self] title, image in
					self?.accessoryTitle = title ?? self?.accessoryTitle
					if let image = image {
						self?.setDisplayIcon(image, 30, .center)
					}
					self?.signalDone()
				}
			}
		} else {
			NSLog("      unknown class")
			allLoadedWell = false
			setDisplayIcon(#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
			signalDone()
			// TODO: generate analyitics report to record what type was received and what UTI
		}
	}

	private func handleLocalFetch(url: URL?, error: Error?) {
		if let url = url {
			let localUrl = copyLocal(url)
			NSLog("      received to local url: \(localUrl.path)")

			if let image = UIImage(contentsOfFile: localUrl.path) {
				setDisplayIcon(image, 10, .fill)
			}
			setBytes(object: localUrl, type: .url)
			signalDone()

		} else if let error = error {
			NSLog("Error fetching local url file representation: \(error.localizedDescription)")
			allLoadedWell = false
		}
	}

	init(provider: NSItemProvider, typeIdentifier: String, parentUuid: UUID, delegate: LoadCompletionDelegate) {

		self.typeIdentifier = typeIdentifier
		self.delegate = delegate
		self.parentUuid = parentUuid

		uuid = UUID()
		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1

		provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
			if let error = error {
				NSLog("      error receiving item: \(error.localizedDescription)")
				self.allLoadedWell = false
				self.setDisplayIcon(#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
				self.signalDone()
			} else if let item = item {
				let receivedTypeString = type(of: item)
				NSLog("item name: [\(provider.suggestedName ?? "")] type: [\(typeIdentifier)] class: [\(receivedTypeString)]")
				self.ingest(item: item, from: provider)
			}
		}
	}

	var displayIcon: UIImage?
	var displayIconPriority: Int
	var displayIconContentMode: ArchivedDropItemDisplayType
	private var displayIconScale: CGFloat
	private func setDisplayIcon(_ icon: UIImage, _ priority: Int, _ contentMode: ArchivedDropItemDisplayType) {
		displayIcon = icon
		displayIconScale = icon.scale
		displayIconPriority = priority
		displayIconContentMode = contentMode
	}

	private func fetchWebPreview(for url: URL, testing: Bool = true, completion: @escaping (String?, UIImage?)->Void) {

		// in thread!!

		if testing {

			NSLog("Investigating possible HTML title from this URL: \(url.absoluteString)")

			var request = URLRequest(url: url)
			request.httpMethod = "HEAD"
			let headFetch = URLSession.shared.dataTask(with: request) { data, response, error in
				if let response = response as? HTTPURLResponse {
					if let type = response.allHeaderFields["Content-Type"] as? String, type.hasPrefix("text/html") {
						NSLog("Content for this is HTML, will try to fetch title")
						self.fetchWebPreview(for: url, testing: false, completion: completion)
					} else {
						NSLog("Content for this isn't HTML, never mind")
						completion(nil, nil)
					}
				}
				if let error = error {
					NSLog("Error while investigating URL: \(error.localizedDescription)")
					completion(nil, nil)
				}
			}
			headFetch.resume()

		} else {

			let fetch = URLSession.shared.dataTask(with: url) { data, response, error in
				if let data = data,
					let text = String(data: data, encoding: .utf8),
					let htmlDoc = try? HTMLDocument(string: text, encoding: .utf8) {

					let title = htmlDoc.title
					if let title = title {
						NSLog("Title located at URL: \(title)")
					} else {
						NSLog("No title located at URL")
					}

					var iconImage: UIImage?

					if var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
						for file in ["/favicon.ico"] {
							c.path = file
							if  let url = c.url,
								let data = try? Data(contentsOf: url, options: []),
								let image = UIImage(data: data) {

								iconImage = image
								break
							}
						}
					}

					completion(title, iconImage)

				} else if let error = error {
					NSLog("Error while fetching title URL: \(error.localizedDescription)")
					completion(nil, nil)
				} else {
					NSLog("Bad HTML data while fetching title URL")
					completion(nil, nil)
				}
			}
			fetch.resume()
		}
	}

	// TODO: MEMORY LEAK BIGTIME

	private func signalDone() {
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

	var displayTitle: String?
	var displayTitlePriority: Int
	var displayTitleAlignment: NSTextAlignment
	private func setTitleInfo(_ text: String?, _ priority: Int) {

		let alignment: NSTextAlignment
		let finalText: String?
		if let text = text, text.characters.count > 200 {
			alignment = .justified
			finalText = text.replacingOccurrences(of: "\n", with: " ")
		} else {
			alignment = .center
			finalText = text
		}
		displayTitle = finalText
		displayTitlePriority = priority
		displayTitleAlignment = alignment
	}

	var itemForShare: (Any?, Int) {

		if typeIdentifier == "public.vcard", let bytes = bytes, let contact = try? CNContactVCardSerialization.contacts(with: bytes) {
			return (contact, 12)
		}

		if typeIdentifier == "com.apple.mapkit.map-item", let item = decode(MKMapItem.self) {
			return (item, 15)
		}

		if let url = decode(NSURL.self) {

			if classType == .url {
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

