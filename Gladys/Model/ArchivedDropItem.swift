
import UIKit

final class ArchivedDropItem: Codable, Equatable {

	let suggestedName: String?
	let uuid: UUID
	var typeItems: [ArchivedDropItemType]
	let createdAt:  Date
	var updatedAt: Date
	var allLoadedWell: Bool
	var isLoading: Bool
	var needsReIngest: Bool
	var note: String
	var titleOverride: String

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
	}

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		suggestedName = try v.decodeIfPresent(String.self, forKey: .suggestedName)
		createdAt = try v.decode(Date.self, forKey: .createdAt)
		updatedAt = try v.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
		uuid = try v.decode(UUID.self, forKey: .uuid)
		typeItems = try v.decode(Array<ArchivedDropItemType>.self, forKey: .typeItems)
		allLoadedWell = try v.decode(Bool.self, forKey: .allLoadedWell)
		needsReIngest = try v.decodeIfPresent(Bool.self, forKey: .needsReIngest) ?? false
		note = try v.decodeIfPresent(String.self, forKey: .note) ?? ""
		titleOverride = try v.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
		isLoading = false
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

	#if MAINAPP || ACTIONEXTENSION

		var loadCount = 0
		weak var delegate: LoadCompletionDelegate?
		private static let blockedSuffixes = [".useractivity", ".internalMessageTransfer", "itemprovider", ".rtfd"]

		init(providers: [NSItemProvider], delegate: LoadCompletionDelegate?) {

			uuid = UUID()
			createdAt = Date()
			updatedAt = createdAt
			suggestedName = providers.first!.suggestedName
			isLoading = true
			allLoadedWell = true
			needsReIngest = false
			titleOverride = ""
			note = ""
			typeItems = [ArchivedDropItemType]()
			self.delegate = delegate

			for provider in providers {
				for typeIdentifier in provider.registeredTypeIdentifiers {
					if !ArchivedDropItem.blockedSuffixes.contains(where: { typeIdentifier.hasSuffix($0) } ) {
						loadCount += 1
						let i = ArchivedDropItemType(provider: provider, typeIdentifier: typeIdentifier, parentUuid: uuid, delegate: self)
						typeItems.append(i)
					}
				}
			}
		}

	#endif

	#if MAINAPP || ACTIONEXTENSION || FILEPROVIDER
		var isDeleting = false
	#endif
}
