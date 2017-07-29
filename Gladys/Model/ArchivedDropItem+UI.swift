
import UIKit
import MapKit
import Contacts
import ContactsUI
import CoreSpotlight

extension ArchivedDropItem {

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
		let fileProviderId = NSFileProviderItemIdentifier(uuid.uuidString)
		Model.signalFileExtension(for: fileProviderId)
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
		typeItems.forEach { $0.registerForDrag(with: p) }

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
			return !item.isFileURL && UIApplication.shared.canOpenURL(item)
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
					if item.isFileURL {
						message = "iOS does not recognise the type of this file"
					} else {
						message = "iOS does not recognise the type of this link"
					}
					genericAlert(title: "Can't Open",
					             message: message,
					             on: viewController)
				}
			}
		}
	}

	var loadingError: (String?, Error?) {
		for item in typeItems {
			if let e = item.loadingError {
				return ("Error processing type \(item.typeIdentifier): ", e)
			}
		}
		return (nil, nil)
	}
}
