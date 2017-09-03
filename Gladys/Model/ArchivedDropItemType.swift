
import UIKit

final class ArchivedDropItemType: Codable {

	private enum CodingKeys : String, CodingKey {
		case typeIdentifier
		case representedClass
		case classWasWrapped
		case uuid
		case parentUuid
		case accessoryTitle
		case displayTitle
		case displayTitleAlignment
		case displayTitlePriority
		case displayIconPriority
		case displayIconContentMode
		case displayIconScale
		case displayIconWidth
		case displayIconHeight
		case createdAt
	}

	func encode(to encoder: Encoder) throws {
		var v = encoder.container(keyedBy: CodingKeys.self)
		try v.encode(typeIdentifier, forKey: .typeIdentifier)
		try v.encode(representedClass, forKey: .representedClass)
		try v.encode(classWasWrapped, forKey: .classWasWrapped)
		try v.encode(uuid, forKey: .uuid)
		try v.encode(parentUuid, forKey: .parentUuid)
		try v.encodeIfPresent(accessoryTitle, forKey: .accessoryTitle)
		try v.encodeIfPresent(displayTitle, forKey: .displayTitle)
		try v.encode(displayTitleAlignment.rawValue, forKey: .displayTitleAlignment)
		try v.encode(displayTitlePriority, forKey: .displayTitlePriority)
		try v.encode(displayIconContentMode.rawValue, forKey: .displayIconContentMode)
		try v.encode(displayIconPriority, forKey: .displayIconPriority)
		try v.encode(displayIconScale, forKey: .displayIconScale)
		try v.encode(displayIconWidth, forKey: .displayIconWidth)
		try v.encode(displayIconHeight, forKey: .displayIconHeight)
		try v.encode(createdAt, forKey: .createdAt)
	}

	lazy var imagePath: URL = {
		return self.folderUrl.appendingPathComponent("thumbnail.png")
	}()

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		typeIdentifier = try v.decode(String.self, forKey: .typeIdentifier)
		representedClass = try v.decode(String.self, forKey: .representedClass)
		classWasWrapped = try v.decode(Bool.self, forKey: .classWasWrapped)
		uuid = try v.decode(UUID.self, forKey: .uuid)
		parentUuid = try v.decode(UUID.self, forKey: .parentUuid)
		accessoryTitle = try v.decodeIfPresent(String.self, forKey: .accessoryTitle)
		displayTitle = try v.decodeIfPresent(String.self, forKey: .displayTitle)
		displayTitlePriority = try v.decode(Int.self, forKey: .displayTitlePriority)
		displayIconPriority = try v.decode(Int.self, forKey: .displayIconPriority)
		displayIconScale = try v.decode(CGFloat.self, forKey: .displayIconScale)
		displayIconWidth = try v.decode(CGFloat.self, forKey: .displayIconWidth)
		displayIconHeight = try v.decode(CGFloat.self, forKey: .displayIconHeight)
		createdAt = try v.decode(Date.self, forKey: .createdAt)

		let a = try v.decode(Int.self, forKey: .displayTitleAlignment)
		displayTitleAlignment = NSTextAlignment(rawValue: a) ?? .center

		let m = try v.decode(Int.self, forKey: .displayIconContentMode)
		displayIconContentMode = ArchivedDropItemDisplayType(rawValue: m) ?? .center
	}

	func setBytes(object: NSSecureCoding, originalData: Data?) {
		if let originalData = originalData {
			bytes = originalData
		} else if let i = object as? NSURL {
			let o = [i.absoluteString] // Safari-style
			bytes = try? PropertyListSerialization.data(fromPropertyList: o, format: .binary, options: 0)
		} else {
			bytes = try? PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
		}
		representedClass = NSStringFromClass(type(of: object))
	}

	var encodedUrl: NSURL? {
		if let u = decode() as? NSURL {
			return u
		} else if let array = decode() as? NSArray {
			for item in array {
				if let text = item as? String, let url = NSURL(string: text), let scheme = url.scheme, !scheme.isEmpty {
					return url
				}
			}
		}
		return nil
	}

	lazy var bytesPath: URL = {
		return self.folderUrl.appendingPathComponent("blob", isDirectory: false)
	}()

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

	let typeIdentifier: String
	var accessoryTitle: String?
	let uuid: UUID
	let parentUuid: UUID
	let createdAt: Date
	var representedClass: String
	var classWasWrapped: Bool
	var loadingError: Error?

	// transient / ui
	weak var delegate: LoadCompletionDelegate?
	var displayIconScale: CGFloat
	var displayIconWidth: CGFloat
	var displayIconHeight: CGFloat
	var loadingAborted = false
	var displayIconPriority: Int
	var displayIconContentMode: ArchivedDropItemDisplayType
	var displayTitle: String?
	var displayTitlePriority: Int
	var displayTitleAlignment: NSTextAlignment

	var contentDescription: String? {
		switch representedClass {
		case "NSData": return "Data"
		case "NSString": return "Text"
		case "NSAttributedString": return "Rich Text"
		case "UIColor": return "Color"
		case "UIImage": return "Image"
		case "MKMapItem": return "Map Location"
		case "NSArray": return "List"
		case "NSDictionary": return "Associative List"
		case "NSURL": return "Link"
		default: return "Data Object (\(representedClass))"
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

		return sizeItem(path: bytesPath)
	}

	var sizeDescription: String? {
		return diskSizeFormatter.string(fromByteCount: sizeInBytes)
	}

	func decode() -> Any? {
		guard let bytes = bytes else { return nil }

		// Do not do this because there may be a URL hidden there
		//if representedClass == "NSData" {
			//return bytes
		//}

		if classWasWrapped {
			return try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(bytes)
		} else if let propertyList = (try? PropertyListSerialization.propertyList(from: bytes, options: [], format: nil)) {
			return propertyList
		} else {
			return bytes
		}
	}

	var displayIcon: UIImage? {
		set {
			let ipath = imagePath
			if let n = newValue {
				n.writeBitmap(to: ipath)
			} else if FileManager.default.fileExists(atPath: ipath.path) {
				try? FileManager.default.removeItem(at: ipath)
			}
		}
		get {
			return UIImage.fromBitmap(at: imagePath, scale: displayIconScale)
		}
	}

	lazy var folderUrl: URL = {
		let url = Model.appStorageUrl.appendingPathComponent(self.parentUuid.uuidString).appendingPathComponent(self.uuid.uuidString)
		let f = FileManager.default
		if !f.fileExists(atPath: url.path) {
			try! f.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		}
		return url
	}()

	var oneTitle: String {
		return accessoryTitle ?? displayTitle ?? typeIdentifier.replacingOccurrences(of: ".", with: "-")
	}

	#if MAINAPP || ACTIONEXTENSION
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
		displayIconWidth = 0
		displayIconHeight = 0
		classWasWrapped = false
		createdAt = Date()
		representedClass = ""

		startIngest(provider: provider)
	}
	#endif
}

