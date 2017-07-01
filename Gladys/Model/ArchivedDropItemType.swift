
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
		case hasLocalFiles
		case createdAt
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
		try v.encode(hasLocalFiles, forKey: .hasLocalFiles)
		try v.encode(createdAt, forKey: .createdAt)
	}

	lazy var imagePath: URL = {
		return self.folderUrl.appendingPathComponent("thumbnail.png")
	}()

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		typeIdentifier = try v.decode(String.self, forKey: .typeIdentifier)
		if let typeValue = try v.decodeIfPresent(String.self, forKey: .classType) {
			classType = ClassType(rawValue: typeValue)
		}
		uuid = try v.decode(UUID.self, forKey: .uuid)
		parentUuid = try v.decode(UUID.self, forKey: .parentUuid)
		allLoadedWell = try v.decode(Bool.self, forKey: .allLoadedWell)
		hasLocalFiles = try v.decode(Bool.self, forKey: .hasLocalFiles)
		accessoryTitle = try v.decodeIfPresent(String.self, forKey: .accessoryTitle)
		displayTitle = try v.decodeIfPresent(String.self, forKey: .displayTitle)
		displayTitlePriority = try v.decode(Int.self, forKey: .displayTitlePriority)
		displayIconPriority = try v.decode(Int.self, forKey: .displayIconPriority)
		displayIconScale = try v.decode(CGFloat.self, forKey: .displayIconScale)
		createdAt = try v.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

		let a = try v.decode(Int.self, forKey: .displayTitleAlignment)
		displayTitleAlignment = NSTextAlignment(rawValue: a) ?? .center

		let m = try v.decode(Int.self, forKey: .displayIconContentMode)
		displayIconContentMode = ArchivedDropItemDisplayType(rawValue: m) ?? .center
	}

	var encodedUrl: NSURL? {
		return decode(NSURL.self)
	}

	lazy var bytesPath: URL = {
		return self.folderUrl.appendingPathComponent("blob", isDirectory: false)
	}()

	var dataExists: Bool {
		return FileManager.default.fileExists(atPath: bytesPath.path)
	}

	var bytes: Data? {
		set {
			//log("setting bytes")
			let byteLocation = bytesPath
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
			let byteLocation = bytesPath
			if FileManager.default.fileExists(atPath: byteLocation.path) {
				return try! Data(contentsOf: byteLocation, options: [.alwaysMapped])
			} else {
				return nil
			}
		}
	}

	lazy var tagDataPath: URL = {
		return self.folderUrl.appendingPathComponent("tags", isDirectory: false)
	}()

	var tagData: Data? {
		set {
			let location = tagDataPath
			if newValue == nil {
				let f = FileManager.default
				if f.fileExists(atPath: location.path) {
					try! f.removeItem(at: location)
				}
			} else {
				try! newValue?.write(to: location, options: [.atomic])
			}
		}
		get {
			let location = tagDataPath
			if FileManager.default.fileExists(atPath: location.path) {
				return try! Data(contentsOf: location, options: [.alwaysMapped])
			} else {
				return nil
			}
		}
	}

	let typeIdentifier: String
	var accessoryTitle: String?
	let uuid: UUID
	let parentUuid: UUID
	let createdAt: Date
	private var classType: ClassType?
	private var hasLocalFiles: Bool
	private var allLoadedWell = true

	// transient / ui
	private weak var delegate: LoadCompletionDelegate?

	private enum ClassType: String {
		case NSString, NSAttributedString, UIColor, UIImage, NSData, MKMapItem, NSURL
	}

	var contentDescription: String? {
		guard let classType = classType else { return nil }

		switch classType {
		case .NSData: return "Raw Data"
		case .NSString: return "Text"
		case .NSAttributedString: return "Rich Text"
		case .UIColor: return "Color"
		case .UIImage: return "Image"
		case .MKMapItem: return "Map Location"
		case .NSURL: return hasLocalFiles ? "File(s)" : "Link"
		}
	}

	var sizeInBytes: Int64 {

		func sizeItem(path: URL) -> Int64 {
			let fm = FileManager.default

			var isDir: ObjCBool = false
			if fm.fileExists(atPath: path.path, isDirectory: &isDir) {

				if isDir.boolValue {
					return fm.contentSizeOfDirectory(at: path)
				} else {
					if let attrs = try? fm.attributesOfItem(atPath: path.path) {
						return attrs[FileAttributeKey.size] as? Int64 ?? 0
					}
				}
			}
			return 0
		}

		if classType == .NSURL && hasLocalFiles, let localUrl = encodedUrl as URL? {
			return sizeItem(path: localUrl)
		}

		return sizeItem(path: bytesPath)
	}

	var sizeDescription: String? {
		return diskSizeFormatter.string(fromByteCount: sizeInBytes)
	}

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
		}
	}

	private func decode<T>(_ type: T.Type) -> T? where T: NSSecureCoding {
		guard let bytes = bytes else { return nil }

		if type == NSData.self {
			return bytes as? T
		}

		let u = NSKeyedUnarchiver(forReadingWith: bytes)
		let className = String(describing: type)
		return u.decodeObject(forKey: className) as? T
	}

	var backgroundInfoObject: (Any?, Int) {
		guard let classType = classType else { return (nil, 0) }

		switch classType {
		case .MKMapItem: return (decode(MKMapItem.self), 30)
		case .UIColor: return (decode(UIColor.self), 10)
		default: return (nil, 0)
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
		case .NSURL:
			return encodedUrl
		}
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
			log("      received string: \(item)")
			setTitleInfo(item as String, 10)
			setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)
			setBytes(object: item, type: .NSString)
			signalDone()

		} else if let item = item as? NSAttributedString {
			log("      received attributed string: \(item)")
			setTitleInfo(item.string, 7)
			setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)
			setBytes(object: item, type: .NSAttributedString)
			signalDone()

		} else if let item = item as? UIColor {
			log("      received color: \(item)")
			setBytes(object: item, type: .UIColor)
			signalDone()

		} else if let item = item as? UIImage {
			log("      received image: \(item)")
			setDisplayIcon(item, 50, .fill)
			setBytes(object: item, type: .UIImage)
			signalDone()

		} else if let item = item as? Data {
			log("      received data: \(item)")
			classType = .NSData
			bytes = item

			if let image = UIImage(data: item) {
				setDisplayIcon(image, 40, .fill)
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

			} else if typeIdentifier == "public.email-message" {
				setDisplayIcon (#imageLiteral(resourceName: "iconEmail"), 10, .center)

			} else if typeIdentifier == "com.apple.mapkit.map-item" {
				setDisplayIcon (#imageLiteral(resourceName: "iconMap"), 5, .center)

			} else if typeIdentifier.hasSuffix(".rtf") {
				if let s = decode(NSAttributedString.self)?.string {
					setTitleInfo(s, 4)
				}
				setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)
			} else if typeIdentifier.hasSuffix(".rtfd") {
				if let s = decode(NSAttributedString.self)?.string {
					setTitleInfo(s, 4)
				}
				setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)
			}

			signalDone()

		} else if let item = item as? MKMapItem {
			log("      received map item: \(item)")
			setBytes(object: item, type: .MKMapItem)
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
				log("      will duplicate item at local path: \(item.path)")
				provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
					if self?.loadingAborted ?? true { return }
					self?.handleLocalFetch(url: url, error: error)
				}
			} else {
				log("      received remote url: \(item.absoluteString)")
				setTitleInfo(item.absoluteString, 6)
				setBytes(object: item as NSURL, type: .NSURL)
				if let s = item.scheme, s.hasPrefix("http") {
					fetchWebPreview(for: item) { [weak self] title, image in
						if self?.loadingAborted ?? true { return }
						self?.accessoryTitle = title ?? self?.accessoryTitle
						if let image = image {
							if image.size.height > 100 || image.size.width > 200 {
								self?.setDisplayIcon(image, 30, .fit)
							} else {
								self?.setDisplayIcon(image, 30, .center)
							}
						}
						self?.signalDone()
					}
				} else {
					signalDone()
				}
			}
		} else {
			log("      unknown class")
			allLoadedWell = false
			setDisplayIcon(#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
			signalDone()
			// TODO: generate analyitics report to record what type was received and what UTI
		}
	}

	private func handleLocalFetch(url: URL?, error: Error?) {
		// in thread
		if let url = url {
			let localUrl = copyLocal(url)
			log("      received to local url: \(localUrl.path)")

			if let image = UIImage(contentsOfFile: localUrl.path) {
				setDisplayIcon(image, 10, .fill)
			}
			setBytes(object: localUrl as NSURL, type: .NSURL)

		} else if let error = error {
			log("Error fetching local data from url: \(error.localizedDescription)")
			allLoadedWell = false
		}
		signalDone()
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
		hasLocalFiles = false
		createdAt = Date()

		provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
			guard let s = self, s.loadingAborted == false else { return }
			if let error = error {
				log("      error receiving item: \(error.localizedDescription)")
				s.allLoadedWell = false
				s.setDisplayIcon(#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
				s.signalDone()
			} else if let item = item {
				let receivedTypeString = type(of: item)
				log("item name: [\(provider.suggestedName ?? "")] type: [\(typeIdentifier)] class: [\(receivedTypeString)]")
				s.ingest(item: item, from: provider)
			}
		}
	}

	private var loadingAborted = false
	func cancelIngest() {
		loadingAborted = true
	}

	var displayIcon: UIImage? {
		set {
			let ipath = imagePath
			if let displayIcon = newValue, let displayIconData = UIImagePNGRepresentation(displayIcon)  {
				try? displayIconData.write(to: ipath, options: [.atomic])
			} else if FileManager.default.fileExists(atPath: ipath.path) {
				try? FileManager.default.removeItem(at: ipath)
			}
		}
		get {
			if 	let cgDataProvider = CGDataProvider(url: imagePath as CFURL),
				let cgImage = CGImage(pngDataProviderSource: cgDataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
				return UIImage(cgImage: cgImage, scale: displayIconScale, orientation: .up)
			} else {
				return nil
			}
		}
	}

	var displayIconPriority: Int
	var displayIconContentMode: ArchivedDropItemDisplayType
	private var displayIconScale: CGFloat
	private func setDisplayIcon(_ icon: UIImage, _ priority: Int, _ contentMode: ArchivedDropItemDisplayType) {
		if contentMode == .center || contentMode == .circle {
			displayIcon = icon
		} else if contentMode == .fit {
			displayIcon = icon.limited(to: CGSize(width: 512, height: 512), limitTo: 0.75, useScreenScale: true)
		} else {
			displayIcon = icon.limited(to: CGSize(width: 512, height: 512), useScreenScale: true)
		}
		displayIconScale = icon.scale
		displayIconPriority = priority
		displayIconContentMode = contentMode
	}

	private func fetchWebPreview(for url: URL, testing: Bool = true, completion: @escaping (String?, UIImage?)->Void) {

		// in thread!!

		if testing {

			log("Investigating possible HTML title from this URL: \(url.absoluteString)")

			var request = URLRequest(url: url)
			request.httpMethod = "HEAD"
			let headFetch = URLSession.shared.dataTask(with: request) { data, response, error in
				if let response = response as? HTTPURLResponse {
					if let type = response.allHeaderFields["Content-Type"] as? String, type.hasPrefix("text/html") {
						log("Content for this is HTML, will try to fetch title")
						self.fetchWebPreview(for: url, testing: false, completion: completion)
					} else {
						log("Content for this isn't HTML, never mind")
						completion(nil, nil)
					}
				}
				if let error = error {
					log("Error while investigating URL: \(error.localizedDescription)")
					completion(nil, nil)
				}
			}
			headFetch.resume()

		} else {

			log("Fetching HTML from URL: \(url.absoluteString)")

			let fetch = URLSession.shared.dataTask(with: url) { data, response, error in
				if let data = data,
					let text = String(data: data, encoding: .utf8),
					let htmlDoc = try? HTMLDocument(string: text, encoding: .utf8) {

					let title = htmlDoc.title?.trimmingCharacters(in: .whitespacesAndNewlines)
					if let title = title {
						log("Title located at URL: \(title)")
					} else {
						log("No title located at URL")
					}

					var largestImagePath = "/favicon.ico"
					var imageRank = 0

					if let touchIcons = htmlDoc.head?.xpath("//link[@rel=\"apple-touch-icon\" or @rel=\"apple-touch-icon-precomposed\" or @rel=\"icon\" or @rel=\"shortcut icon\"]") {
						for node in touchIcons {
							let isTouch = node.attr("rel")?.hasPrefix("apple-touch-icon") ?? false
							var rank = isTouch ? 10 : 1
							if let sizes = node.attr("sizes") {
								let numbers = sizes.split(separator: "x").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
								if numbers.count > 1 {
									rank = (Int(numbers[0]) ?? 1) * (Int(numbers[1]) ?? 1) * (isTouch ? 100 : 1)
								}
							}
							if let href = node.attr("href") {
								if rank > imageRank {
									imageRank = rank
									largestImagePath = href
								}
							}
						}
					}

					var iconImage: UIImage?
					var iconUrl: URL?
					if let i = URL(string: largestImagePath), i.scheme != nil {
						iconUrl = i
					} else {
						if var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
							c.path = largestImagePath
							iconUrl = c.url
						}
					}

					if let url = iconUrl, let data = try? Data(contentsOf: url, options: []), let image = UIImage(data: data) {
						iconImage = image
					}

					completion(title, iconImage)

				} else if let error = error {
					log("Error while fetching title URL: \(error.localizedDescription)")
					completion(nil, nil)
				} else {
					log("Bad HTML data while fetching title URL")
					completion(nil, nil)
				}
			}
			fetch.resume()
		}
	}

	// TODO: MEMORY LEAK BIGTIME

	private func signalDone() {
		if !loadingAborted {
			DispatchQueue.main.async {
				self.delegate?.loadCompleted(sender: self, success: self.allLoadedWell)
			}
		}
	}

	lazy var folderUrl: URL = {
		let url = NSFileProviderManager.default.documentStorageURL.appendingPathComponent(self.parentUuid.uuidString).appendingPathComponent(self.uuid.uuidString)
		let f = FileManager.default
		if !f.fileExists(atPath: url.path) {
			try! f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}
		return url
	}()

	private func copyLocal(_ url: URL) -> URL {

		hasLocalFiles = true
		
		let newUrl = folderUrl.appendingPathComponent(url.lastPathComponent)
		let f = FileManager.default
		do {
			if f.fileExists(atPath: newUrl.path) {
				try f.removeItem(at: newUrl)
			}
			try f.copyItem(at: url, to: newUrl)
		} catch {
			log("Error while copying item: \(error.localizedDescription)")
			allLoadedWell = false
		}
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

	var oneTitle: String {
		return accessoryTitle ?? displayTitle ?? typeIdentifier.replacingOccurrences(of: ".", with: "-")
	}

	var dragItem: UIDragItem {

		let p = NSItemProvider()
		p.suggestedName = oneTitle
		register(with: p)

		let i = UIDragItem(itemProvider: p)
		i.localObject = ["local_object": self]
		return i
	}
}

