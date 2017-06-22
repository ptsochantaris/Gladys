
import UIKit
import MapKit
import Contacts
import CoreSpotlight

final class ArchivedDropItem: Codable, LoadCompletionDelegate {

	let uuid: UUID
	private let suggestedName: String?
	private var typeItems: [ArchivedDropItemType]!
	private let createdAt:  Date

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
		loadCount = 0
	}

	// fulfill drag and drop promise from search drag!

	func makeIndex() {

		guard let firstItem = typeItems.first else { return }

		let attributes = CSSearchableItemAttributeSet(itemContentType: firstItem.typeIdentifier)
		attributes.title = displayTitle.0
		attributes.contentDescription = accessoryTitle
		attributes.thumbnailURL = firstItem.imagePath
		attributes.keywords = ["Gladys"]
		attributes.providerDataTypeIdentifiers = typeItems.map { $0.typeIdentifier }
		attributes.userCurated = true
		attributes.contentCreationDate = createdAt

		let item = CSSearchableItem(uniqueIdentifier: uuid.uuidString, domainIdentifier: nil, attributeSet: attributes)
		CSSearchableIndex.default().indexSearchableItems([item], completionHandler: { error in
			if let error = error {
				NSLog("Error indexing item \(self.uuid): \(error)")
			}
			NSLog("-------------------------")
		})
	}

	func delete() {
		CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [uuid.uuidString]) { error in
			if let error = error {
				NSLog("Error while deleting an index \(error)")
			}
		}
		let f = FileManager.default
		if f.fileExists(atPath: folderUrl.path) {
			try! f.removeItem(at: folderUrl)
		}
	}

	var displayInfo: ArchivedDropDisplayInfo {

		let (img, contentMode) = displayIcon
		let (title, alignment) = displayTitle

		let info = ArchivedDropDisplayInfo(
			image: img,
			imageContentMode: contentMode,
			title: title,
			accessoryText: accessoryTitle,
			titleAlignment: alignment)

		return info
	}

	var backgroundInfoObject: Any? {
		var currentItem: Any?
		var currentPriority = -1
		for item in typeItems {
			let (newItem, newPriority) = item.backgroundInfoObject
			if let newItem = newItem, newPriority > currentPriority {
				currentItem = newItem
				currentPriority = newPriority
			}
		}
		return currentItem
	}

	var dragItem: UIDragItem {

		let p = NSItemProvider()
		p.suggestedName = suggestedName
		typeItems.forEach { $0.register(with: p) }

		let i = UIDragItem(itemProvider: p)
		i.localObject = self
		return i
	}

	#if MAINAPP

	func tryOpen() {
		var priority = -1
		var item: Any?
		for i in typeItems {
			let (newItem, newPriority) = i.itemForShare
			if let newItem = newItem, newPriority > priority {
				item = newItem
				priority = newPriority
			}
		}
		if let item = item as? MKMapItem {
			item.openInMaps(launchOptions: [ MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault ])
		} else if let _ = item as? CNContact {
			// TODO
		} else if let item = item as? URL {
			UIApplication.shared.open(item, options: [:]) { success in
				if !success {
					let message: String
					if item.scheme == "file" {
						message = "iOS does not recognise the type of this file"
					} else {
						message = "iOS does not recognise the type of this link"
					}
					let a = UIAlertController(title: "Can't Open", message: message, preferredStyle: .alert)
					a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
					UIApplication.shared.windows.first!.rootViewController!.present(a, animated: true)
				}
			}
		}
	}

	#endif

	private var displayIcon: (UIImage?, ArchivedDropItemDisplayType) {
		var priority = -1
		var image: UIImage?
		var contentMode = ArchivedDropItemDisplayType.center
		for i in typeItems {
			let newImage = i.displayIcon
			let newPriority = i.displayIconPriority
			if let newImage = newImage, newPriority > priority {
				image = newImage
				priority = newPriority
				contentMode = i.displayIconContentMode
			}
		}

		if image == nil {
			image = #imageLiteral(resourceName: "iconStickyNote")
			contentMode = .center
		}

		return (image, contentMode)
	}

	private var displayTitle: (String?, NSTextAlignment) {

		if let suggestedName = suggestedName {
			return (suggestedName, .center)
		}

		var title: String?
		var priority = 0
		var alignment = NSTextAlignment.center
		for i in typeItems {
			let newTitle = i.displayTitle
			let newPriority = i.displayTitlePriority
			if let newTitle = newTitle, newPriority > priority {
				title = newTitle
				priority = newPriority
				alignment = i.displayTitleAlignment
			}
		}
		return (title, alignment)
	}

	private var accessoryTitle: String? {
		return typeItems.first(where: { $0.accessoryTitle != nil })?.accessoryTitle
	}

	private lazy var folderUrl: URL = {
		let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
		return docs.appendingPathComponent(self.uuid.uuidString)
	}()

	init(provider: NSItemProvider, delegate: LoadCompletionDelegate?) {

		uuid = UUID()
		createdAt = Date()
		suggestedName = provider.suggestedName
		loadCount = provider.registeredTypeIdentifiers.count
		isLoading = true
		allLoadedWell = true
		self.delegate = delegate

		typeItems = provider.registeredTypeIdentifiers.map {
			ArchivedDropItemType(provider: provider, typeIdentifier: $0, parentUuid: uuid, delegate: self)
		}
	}

	func bytes(for type: String) -> Data? {
		return typeItems.first(where: { $0.typeIdentifier == type })?.bytes
	}

	func url(for type: String) -> NSURL? {
		return typeItems.first(where: { $0.typeIdentifier == type })?.encodedUrl
	}

	//////////////////////////

	weak var delegate: LoadCompletionDelegate?
	var isLoading: Bool
	var allLoadedWell: Bool

	private var loadCount: Int
	func loadCompleted(sender: AnyObject, success: Bool) {
		if !success { allLoadedWell = false }
		loadCount = loadCount - 1
		if loadCount == 0 {
			isLoading = false
			delegate?.loadCompleted(sender: self, success: allLoadedWell)
		}
	}
}
