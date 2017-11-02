
import UIKit
import MapKit
import CloudKit
import Contacts
import ContactsUI
import CoreSpotlight
import MobileCoreServices

extension ArchivedDropItem {

	func delete() {
		isDeleting = true
		CloudManager.markAsDeleted(uuid: uuid)
		CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [uuid.uuidString]) { error in
			if let error = error {
				log("Error while deleting an index \(error)")
			}
		}
		let f = FileManager.default
		if f.fileExists(atPath: folderUrl.path) {
			try! f.removeItem(at: folderUrl)
		}
	}

	var shouldDisplayLoading: Bool {
		return needsReIngest || loadingProgress != nil
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

	private var itemProvider: NSItemProvider {
		let p = NSItemProvider()
		p.suggestedName = suggestedName
		typeItems.forEach { $0.register(with: p) }
		return p
	}

	var dragItem: UIDragItem {
		let i = UIDragItem(itemProvider: itemProvider)
		i.localObject = self
		return i
	}

	func copyToPasteboard() {
		UIPasteboard.general.setItemProviders([itemProvider], localOnly: false, expirationDate: nil)
	}

	func dragItem(forLabelIndex index: Int) -> UIDragItem? {

		guard index < labels.count else {
			return nil
		}

		let label = labels[index]

		let p = NSItemProvider(item: label as NSSecureCoding, typeIdentifier: kUTTypePlainText as String)
		let i = UIDragItem(itemProvider: p)
		i.localObject = label
		return i
	}

	var addedString: String {
		let d = DateFormatter()
		d.doesRelativeDateFormatting = true
		d.dateStyle = .medium
		d.timeStyle = .medium
		return "Added " + d.string(from: createdAt) + "\n" + diskSizeFormatter.string(fromByteCount: sizeInBytes)
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

	var canPreview: Bool {
		return typeItems.contains { $0.canPreview }
	}

	func tryPreview(in: UIViewController, from: ArchivedItemCell) {
		if let t = typeItems.first(where:{ $0.canPreview }) {
			let q = t.quickLook(extraRightButton: nil)
			let n = UINavigationController(rootViewController: q)
			if let s = UIApplication.shared.windows.first?.bounds.size {
				n.preferredContentSize = s
			}
			n.view.tintColor = ViewController.shared.view.tintColor
			n.modalPresentationStyle = .popover
			if ViewController.shared.phoneMode || UIAccessibilityIsVoiceOverRunning() {
				let r = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(previewDone))
				q.navigationItem.rightBarButtonItem = r
			}
			ViewController.shared.present(n, animated: true)
			if let p = q.popoverPresentationController {
				p.sourceView = from
				p.sourceRect = from.contentView.bounds.insetBy(dx: 6, dy: 6)
			}
		}
	}

	@objc private func previewDone() {
		ViewController.shared.dismissAnyPopOver()
	}

	func tryOpen(in viewController: UINavigationController, completion: @escaping (Bool)->Void) {
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
			completion(true)
		} else if let contact = item as? CNContact {
			let c = CNContactViewController(forUnknownContact: contact)
			c.contactStore = CNContactStore()
			c.hidesBottomBarWhenPushed = true
			viewController.pushViewController(c, animated: true)
			completion(false)
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
				completion(success)
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
