
import UIKit
import MapKit
import Contacts

final class ArchivedDropDisplayInfo {
	var image: UIImage?
	var imageContentMode = UIViewContentMode.center
	var title: String?
	var accessoryText: String?
	var titleAlignment = NSTextAlignment.center
}

final class ArchivedDropItem: LoadCompletionCounter, Codable {

	private let uuid: UUID
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

		super.init(loadCount: 0, delegate: nil)
		allLoadedWell = try v.decode(Bool.self, forKey: .allLoadedWell)
		isLoading = false
	}

	func delete() {
		let f = FileManager.default
		if f.fileExists(atPath: folderUrl.path) {
			try! f.removeItem(at: folderUrl)
		}
	}

	var displayInfo: ArchivedDropDisplayInfo {

		let info = ArchivedDropDisplayInfo()

		let (img, contentMode) = displayIcon
		info.imageContentMode = contentMode
		info.image = img

		let (title, alignment) = displayTitle
		info.titleAlignment = alignment
		info.title = title

		info.accessoryText = accessoryTitle

		if info.image == nil {
			info.image = #imageLiteral(resourceName: "iconStickyNote")
			info.imageContentMode = .center
		}

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
		for item in typeItems {
			item.register(with: p)
		}

		let i = UIDragItem(itemProvider: p)
		i.localObject = self
		return i
	}

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

	private var displayIcon: (UIImage?, UIViewContentMode) {
		var priority = -1
		var image: UIImage?
		var contentMode = UIViewContentMode.center
		for i in typeItems {
			let newImage = i.displayIcon
			let newPriority = i.displayIconPriority
			if let newImage = newImage, newPriority > priority {
				image = newImage
				priority = newPriority
				contentMode = i.displayIconContentMode
			}
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
		for i in typeItems {
			if let t = i.accessoryTitle {
				return t
			}
		}
		return nil
	}

	private lazy var folderUrl: URL = {
		let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
		return docs.appendingPathComponent(self.uuid.uuidString)
	}()

	init(provider: NSItemProvider, delegate: LoadCompletionDelegate?) {

		uuid = UUID()
		createdAt = Date()
		suggestedName = provider.suggestedName

		super.init(loadCount: provider.registeredTypeIdentifiers.count, delegate: delegate)

		typeItems = provider.registeredTypeIdentifiers.map {
			ArchivedDropItemType(provider: provider, typeIdentifier: $0, parentUuid: uuid, delegate: self)
		}
	}

	override func loadCompleted(success: Bool) {
		super.loadCompleted(success: success)
		Model.save()
	}

	//////////////////////////
}
