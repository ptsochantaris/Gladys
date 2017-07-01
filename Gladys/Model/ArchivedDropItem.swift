
import UIKit
import MapKit
import Contacts
import ContactsUI
import CoreSpotlight
import FileProvider

final class ArchivedDropItem: Codable, LoadCompletionDelegate {

	let uuid: UUID
	var typeItems: [ArchivedDropItemType]!
	private let suggestedName: String?
	let createdAt:  Date

	var isDeleting = false

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

	func makeIndex(completion: ((Bool)->Void)? = nil) {

		guard let firstItem = typeItems.first else { return }

		let attributes = CSSearchableItemAttributeSet(itemContentType: firstItem.typeIdentifier)
		attributes.title = displayTitle.0
		attributes.contentDescription = accessoryTitle
		attributes.thumbnailURL = firstItem.imagePath
		attributes.providerDataTypeIdentifiers = typeItems.map { $0.typeIdentifier }
		attributes.userCurated = true
		attributes.addedDate = createdAt

		let item = CSSearchableItem(uniqueIdentifier: uuid.uuidString, domainIdentifier: nil, attributeSet: attributes)
		CSSearchableIndex.default().indexSearchableItems([item], completionHandler: { error in
			if let error = error {
				log("Error indexing item \(self.uuid): \(error)")
				completion?(false)
			} else {
				log("Item indexed: \(self.uuid)")
				completion?(true)
			}
		})
	}

	func delete() {
		isDeleting = true
		CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [uuid.uuidString]) { error in
			if let error = error {
				log("Error while deleting an index \(error)")
			}
		}
		let f = FileManager.default
		if f.fileExists(atPath: folderUrl.path) {
			try! f.removeItem(at: folderUrl)
		}
		NSFileProviderManager.default.signalEnumerator(forContainerItemIdentifier: NSFileProviderItemIdentifier(uuid.uuidString)) { error in
			if let e = error {
				log("Error signalling deletion of item: \(e.localizedDescription)")
			}
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

	var oneTitle: String {
		return accessoryTitle ?? displayTitle.0 ?? uuid.uuidString
	}

	#if MAINAPP

	var dragItem: UIDragItem {

		let p = NSItemProvider()
		p.suggestedName = suggestedName
		typeItems.forEach { $0.register(with: p) }

		let i = UIDragItem(itemProvider: p)
		i.localObject = self
		return i
	}

	var shareableComponents: [Any] {
		var items = typeItems.flatMap { $0.itemForShare.0 }
		if let a = accessoryTitle {
			items.append(a)
		}
		return items
	}

	var canOpen: Bool {
		var priority = -1
		var item: Any?

		for i in typeItems {
			let (newItem, newPriority) = i.itemForShare
			if let newItem = newItem, newPriority > priority {
				item = newItem
				priority = newPriority
			}
		}

		if item is MKMapItem {
			return true
		} else if item is CNContact {
			return true
		} else if let item = item as? URL {
			return item.scheme != "file" && UIApplication.shared.canOpenURL(item)
		}

		return false
	}

	func tryOpen(in viewController: UINavigationController) {
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
			item.openInMaps(launchOptions: [:])
		} else if let contact = item as? CNContact {
			let c = CNContactViewController(forUnknownContact: contact)
			c.contactStore = CNContactStore()
			c.hidesBottomBarWhenPushed = true
			viewController.pushViewController(c, animated: true)
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
					viewController.present(a, animated: true)
				}
			}
		}
	}

	#endif

	var sizeInBytes: Int64 {
		return typeItems.reduce(0, { $0 + $1.sizeInBytes })
	}

	private var displayIcon: (UIImage?, ArchivedDropItemDisplayType) {
		let highestPriorityIconItem = typeItems.max(by: { $0.displayIconPriority < $1.displayIconPriority })
		let contentMode = highestPriorityIconItem?.displayIconContentMode ?? .center
		let image = highestPriorityIconItem?.displayIcon ?? #imageLiteral(resourceName: "iconStickyNote")
		return (image, contentMode)
	}

	private var displayTitle: (String?, NSTextAlignment) {

		if let suggestedName = suggestedName {
			return (suggestedName, .center)
		}

		let highestPriorityItem = typeItems.max(by: { $0.displayTitlePriority < $1.displayTitlePriority })
		let title = highestPriorityItem?.displayTitle
		let alignment = highestPriorityItem?.displayTitleAlignment ?? .center
		return (title, alignment)
	}

	private var accessoryTitle: String? {
		return typeItems.first(where: { $0.accessoryTitle != nil })?.accessoryTitle
	}

	private lazy var folderUrl: URL = {
		return NSFileProviderManager.default.documentStorageURL.appendingPathComponent(self.uuid.uuidString)
	}()

	private static let blockedSuffixes = [".useractivity", ".internalMessageTransfer"]

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

	func bytes(for type: String) -> Data? {
		return typeItems.first(where: { $0.typeIdentifier == type })?.bytes
	}

	func url(for type: String) -> NSURL? {
		return typeItems.first(where: { $0.typeIdentifier == type })?.encodedUrl
	}

	func cancelIngest() {
		typeItems.forEach { $0.cancelIngest() }
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

	//////////////////////////

	weak var delegate: LoadCompletionDelegate?
	var isLoading: Bool
	var allLoadedWell: Bool
	var loadCount: Int
	func loadCompleted(sender: AnyObject, success: Bool) {
		if !success { allLoadedWell = false }
		loadCount = loadCount - 1
		if loadCount == 0 {
			isLoading = false
			delegate?.loadCompleted(sender: self, success: allLoadedWell)
		}
	}
	func loadingProgress(sender: AnyObject) { }

	////////////////////////////

	var loadingError: (String?, Error?) {
		for item in typeItems {
			if let e = item.loadingError {
				return ("Error processing type \(item.typeIdentifier): ", e)
			}
		}
		return ("Error while loading items: ", NSError(domain: "build.bru.Gladys.loadError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Generic loading error"]))
	}
}
