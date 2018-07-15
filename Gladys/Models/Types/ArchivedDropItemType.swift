
import UIKit
import MobileCoreServices
import CloudKit

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
		case displayIconTemplate
		case createdAt
		case updatedAt
		case needsDeletion
		case order
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
		try v.encode(updatedAt, forKey: .updatedAt)
		try v.encode(displayIconTemplate, forKey: .displayIconTemplate)
		try v.encode(needsDeletion, forKey: .needsDeletion)
		try v.encode(order, forKey: .order)
	}

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		typeIdentifier = try v.decode(String.self, forKey: .typeIdentifier)
		representedClass = try v.decode(RepresentedClass.self, forKey: .representedClass)
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
		displayIconTemplate = try v.decodeIfPresent(Bool.self, forKey: .displayIconTemplate) ?? false
		needsDeletion = try v.decodeIfPresent(Bool.self, forKey: .needsDeletion) ?? false
		order = try v.decodeIfPresent(Int.self, forKey: .order) ?? 0

		let c = try v.decode(Date.self, forKey: .createdAt)
		createdAt = c
		updatedAt = try v.decodeIfPresent(Date.self, forKey: .updatedAt) ?? c

		let a = try v.decode(Int.self, forKey: .displayTitleAlignment)
		displayTitleAlignment = NSTextAlignment(rawValue: a) ?? .center

		let m = try v.decode(Int.self, forKey: .displayIconContentMode)
		displayIconContentMode = ArchivedDropItemDisplayType(rawValue: m) ?? .center

		isTransferring = false
	}

	var typeIdentifier: String
	var accessoryTitle: String?
	let uuid: UUID
	let parentUuid: UUID
	let createdAt: Date
	var updatedAt: Date
	var representedClass: RepresentedClass
	var classWasWrapped: Bool
	var loadingError: Error?
	var needsDeletion: Bool
	var order: Int

	// transient / ui
	weak var delegate: LoadCompletionDelegate?
	var displayIconScale: CGFloat
	var displayIconWidth: CGFloat
	var displayIconHeight: CGFloat
	var loadingAborted = false
	var displayIconPriority: Int
	var displayIconContentMode: ArchivedDropItemDisplayType
	var displayIconTemplate: Bool
	var displayTitle: String?
	var displayTitlePriority: Int
	var displayTitleAlignment: NSTextAlignment
	var ingestCompletion: (()->Void)?
	var isTransferring: Bool

	// Caches
	var encodedURLCache: (Bool, NSURL?)?
	var canPreviewCache: Bool?

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
			let i = UIImage.fromBitmap(at: imagePath, scale: displayIconScale)
			if displayIconTemplate {
				return i?.withRenderingMode(.alwaysTemplate)
			} else {
				return i
			}
		}
	}

	#if MAINAPP
	init(typeIdentifier: String, parentUuid: UUID, data: Data, order: Int) {

		self.typeIdentifier = typeIdentifier
		self.parentUuid = parentUuid
		self.order = order

		uuid = UUID()
		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = false
		classWasWrapped = false
		needsDeletion = false
		createdAt = Date()
		updatedAt = createdAt
		representedClass = .data
		delegate = nil
		bytes = data
	}
	#endif

	#if MAINAPP || ACTIONEXTENSION
	init(typeIdentifier: String, parentUuid: UUID, delegate: LoadCompletionDelegate, order: Int) {

		self.typeIdentifier = typeIdentifier
		self.delegate = delegate
		self.parentUuid = parentUuid
		self.order = order

		uuid = UUID()
		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = true
		classWasWrapped = false
		needsDeletion = false
		createdAt = Date()
		updatedAt = createdAt
		representedClass = .unknown(name: "")
	}
	#endif

	init(from record: CKRecord, parentUuid: UUID) {

		self.parentUuid = parentUuid

		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = false
		needsDeletion = false

		let myUUID = record.recordID.recordName
		uuid = UUID(uuidString: myUUID)!
		createdAt = record["createdAt"] as! Date
		updatedAt = record["updatedAt"] as! Date
		typeIdentifier = record["typeIdentifier"] as! String
		representedClass = RepresentedClass(name: record["representedClass"] as! String)
		classWasWrapped = (record["classWasWrapped"] as! Int != 0)
		accessoryTitle = record["accessoryTitle"] as? String
		order = record["order"] as? Int ?? 0
		if let assetURL = (record["bytes"] as? CKAsset)?.fileURL {
			try? FileManager.default.copyAndReplaceItem(at: assetURL, to: bytesPath)
		}
		cloudKitRecord = record
	}

	init(from typeItem: ArchivedDropItemType, newParent: ArchivedDropItem) {
		parentUuid = newParent.uuid

		displayIconPriority = 0
		displayIconContentMode = .center
		displayTitlePriority = 0
		displayTitleAlignment = .center
		displayIconScale = 1
		displayIconWidth = 0
		displayIconHeight = 0
		displayIconTemplate = false
		isTransferring = false
		needsDeletion = false
		order = Int.max
		delegate = nil

		uuid = UUID()
		createdAt = Date()
		updatedAt = Date()
		typeIdentifier = typeItem.typeIdentifier
		representedClass = typeItem.representedClass
		classWasWrapped = typeItem.classWasWrapped
		accessoryTitle = typeItem.accessoryTitle
		bytes = typeItem.bytes
	}
}

