
import UIKit

final class ArchivedDropItem: Codable, Equatable {

	let suggestedName: String?
	let uuid: UUID
	var typeItems: [ArchivedDropItemType]
	let createdAt:  Date
	var updatedAt: Date
	var allLoadedWell: Bool
	var needsReIngest: Bool
	var needsCloudPush: Bool
	var note: String
	var titleOverride: String
	var labels: [String]

	// Transient
	var loadingProgress: Progress?

	private enum CodingKeys : String, CodingKey {
		case suggestedName
		case typeItems
		case createdAt
		case updatedAt
		case uuid
		case allLoadedWell
		case needsReIngest
		case note
		case titleOverride
		case labels
		case needsCloudPush
	}

	func encode(to encoder: Encoder) throws {
		var v = encoder.container(keyedBy: CodingKeys.self)
		try v.encodeIfPresent(suggestedName, forKey: .suggestedName)
		try v.encode(createdAt, forKey: .createdAt)
		try v.encode(updatedAt, forKey: .updatedAt)
		try v.encode(uuid, forKey: .uuid)
		try v.encode(typeItems, forKey: .typeItems)
		try v.encode(allLoadedWell, forKey: .allLoadedWell)
		try v.encode(needsReIngest, forKey: .needsReIngest)
		try v.encode(note, forKey: .note)
		try v.encode(titleOverride, forKey: .titleOverride)
		try v.encode(labels, forKey: .labels)
		try v.encode(needsCloudPush, forKey: .needsCloudPush)
	}

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		suggestedName = try v.decodeIfPresent(String.self, forKey: .suggestedName)
		let c = try v.decode(Date.self, forKey: .createdAt)
		createdAt = c
		updatedAt = try v.decodeIfPresent(Date.self, forKey: .updatedAt) ?? c
		uuid = try v.decode(UUID.self, forKey: .uuid)
		typeItems = try v.decode(Array<ArchivedDropItemType>.self, forKey: .typeItems)
		allLoadedWell = try v.decode(Bool.self, forKey: .allLoadedWell)
		needsReIngest = try v.decodeIfPresent(Bool.self, forKey: .needsReIngest) ?? false
		note = try v.decodeIfPresent(String.self, forKey: .note) ?? ""
		titleOverride = try v.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
		labels = try v.decodeIfPresent([String].self, forKey: .labels) ?? []
		needsCloudPush = try v.decodeIfPresent(Bool.self, forKey: .needsCloudPush) ?? false
	}

	static func == (lhs: ArchivedDropItem, rhs: ArchivedDropItem) -> Bool {
		return lhs.uuid == rhs.uuid
	}

	var oneTitle: String {
		return accessoryTitle ?? displayTitle.0 ?? uuid.uuidString
	}

	var sizeInBytes: Int64 {
		return typeItems.reduce(0, { $0 + $1.sizeInBytes })
	}

	var imagePath: URL? {
		let highestPriorityIconItem = typeItems.max(by: { $0.displayIconPriority < $1.displayIconPriority })
		return highestPriorityIconItem?.imagePath
	}

	var displayIcon: UIImage {
		let highestPriorityIconItem = typeItems.max(by: { $0.displayIconPriority < $1.displayIconPriority })
		return highestPriorityIconItem?.displayIcon ?? #imageLiteral(resourceName: "iconStickyNote")
	}

	var dominantTypeDescription: String? {
		let highestPriorityIconItem = typeItems.max(by: { $0.displayIconPriority < $1.displayIconPriority })
		return highestPriorityIconItem?.typeDescription
	}

	var displayMode: ArchivedDropItemDisplayType {
		let highestPriorityIconItem = typeItems.max(by: { $0.displayIconPriority < $1.displayIconPriority })
		return highestPriorityIconItem?.displayIconContentMode ?? .center
	}

	var displayTitle: (String?, NSTextAlignment) {

		let highestPriorityItem = typeItems.max(by: { $0.displayTitlePriority < $1.displayTitlePriority })
		let title = highestPriorityItem?.displayTitle
		let alignment = highestPriorityItem?.displayTitleAlignment ?? .center
		if let title = title {
			return (title, alignment)
		} else {
			return (suggestedName, .center)
		}
	}

	var accessoryTitle: String? {
		if titleOverride.isEmpty {
			return typeItems.first(where: { $0.accessoryTitle != nil })?.accessoryTitle
		} else {
			return titleOverride
		}
	}

	lazy var folderUrl: URL = {
		return Model.appStorageUrl.appendingPathComponent(self.uuid.uuidString)
	}()

	func bytes(for type: String) -> Data? {
		return typeItems.first(where: { $0.typeIdentifier == type })?.bytes
	}

	func url(for type: String) -> NSURL? {
		return typeItems.first(where: { $0.typeIdentifier == type })?.encodedUrl
	}

	func markUpdated() {
		updatedAt = Date()
		needsCloudPush = true
	}

	#if MAINAPP || ACTIONEXTENSION

		var loadCount = 0
		weak var delegate: LoadCompletionDelegate?

		init(providers: [NSItemProvider], delegate: LoadCompletionDelegate?) {

			uuid = UUID()
			createdAt = Date()
			updatedAt = createdAt
			suggestedName = providers.first!.suggestedName
			allLoadedWell = true
			needsReIngest = true
			needsCloudPush = true
			titleOverride = ""
			note = ""
			labels = []
			typeItems = [ArchivedDropItemType]()
			self.delegate = delegate

			loadingProgress = startIngest(providers: providers)
		}

	#endif

	#if MAINAPP || ACTIONEXTENSION || FILEPROVIDER
		var isDeleting = false
	#endif
}
