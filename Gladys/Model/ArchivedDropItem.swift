
import UIKit

final class ArchivedDropItem: Codable {

	let suggestedName: String?
	let uuid: UUID
	var typeItems: [ArchivedDropItemType]!
	let createdAt:  Date
	var allLoadedWell: Bool
	var isLoading: Bool

	private enum CodingKeys : String, CodingKey {
		case suggestedName
		case typeItems
		case createdAt
		case uuid
		case allLoadedWell
	}

	func encode(to encoder: Encoder) throws {
		var v = encoder.container(keyedBy: CodingKeys.self)
		try v.encodeIfPresent(suggestedName, forKey: .suggestedName)
		try v.encode(createdAt, forKey: .createdAt)
		try v.encode(uuid, forKey: .uuid)
		try v.encode(typeItems, forKey: .typeItems)
		try v.encode(allLoadedWell, forKey: .allLoadedWell)
	}

	init(from decoder: Decoder) throws {
		let v = try decoder.container(keyedBy: CodingKeys.self)
		suggestedName = try v.decodeIfPresent(String.self, forKey: .suggestedName)
		createdAt = try v.decode(Date.self, forKey: .createdAt)
		uuid = try v.decode(UUID.self, forKey: .uuid)
		typeItems = try v.decode(Array<ArchivedDropItemType>.self, forKey: .typeItems)
		allLoadedWell = try v.decode(Bool.self, forKey: .allLoadedWell)
		isLoading = false
	}

	var oneTitle: String {
		return accessoryTitle ?? displayTitle.0 ?? uuid.uuidString
	}

	var sizeInBytes: Int64 {
		return typeItems.reduce(0, { $0 + $1.sizeInBytes })
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
		return typeItems.first(where: { $0.accessoryTitle != nil })?.accessoryTitle
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
		private static let blockedSuffixes = [".useractivity", ".internalMessageTransfer", "itemprovider"]

		init(provider: NSItemProvider, delegate: LoadCompletionDelegate?) {

			let ids = provider.registeredTypeIdentifiers.filter({ typeIdentifier in
				!ArchivedDropItem.blockedSuffixes.contains(where: { blockedSuffix in typeIdentifier.hasSuffix(blockedSuffix )})
			})

			uuid = UUID()
			createdAt = Date()
			suggestedName = provider.suggestedName
			loadCount = ids.count
			isLoading = true
			allLoadedWell = true
			self.delegate = delegate

			typeItems = ids.map {
				ArchivedDropItemType(provider: provider, typeIdentifier: $0, parentUuid: uuid, delegate: self)
			}
		}

		func cancelIngest() {
			typeItems.forEach { $0.cancelIngest() }
		}

	#endif


	#if MAINAPP || ACTIONEXTENSION || FILEPROVIDER
		var isDeleting = false
	#endif
}
