
import UIKit
import MapKit
import CloudKit
import Contacts
import ContactsUI
import CoreSpotlight
import MobileCoreServices
import GladysFramework

extension ArchivedDropItem {

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

	private func getPassword(from: UIViewController, title: String, action: String, requestHint: Bool, message: String, completion: @escaping (String?, String?)->Void) {
		let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
		a.addTextField { textField in
			textField.placeholder = "Password"
			textField.isSecureTextEntry = true
		}
		if requestHint {
			a.addTextField { [weak self] textField in
				textField.placeholder = "Label when locked"
				textField.text = self?.displayText.0
			}
		}
		a.addAction(UIAlertAction(title: action, style: .default) { [weak self] ac in

			var hint: String?
			if a.textFields!.count > 1 {
				hint = a.textFields![1].text
			}

			let password = a.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			if password.isEmpty {
				self?.getPassword(from: from, title: title, action: action, requestHint: requestHint, message: message, completion: completion)
			} else {
				completion(password, hint)
			}
		})
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { ac in
			completion(nil, nil)
		})
		from.present(a, animated: true)
	}

	func lock(from: UIViewController, completion: @escaping (Data?, String?)->Void) {
		let message: String
        if LocalAuth.canUseLocalAuth {
			message = "Please provide a backup password in case TouchID or FaceID fails. You can also provide an optional label to display while the item is locked."
		} else {
			message = "Please provide the password you will use to unlock this item. You can also provide an optional label to display while the item is locked."
		}
		getPassword(from: from, title: "Lock Item", action: "Lock", requestHint: true, message: message) { [weak self] password, hint in
			guard let password = password else {
				completion(nil, nil)
				return
			}
			self?.needsUnlock = true
			completion(sha1(password), hint)
		}
	}

    private static var unlockingItemsBlock = Set<UUID>()
	func unlock(from: UIViewController, label: String, action: String, completion: @escaping (Bool)->Void) {
        if ArchivedDropItem.unlockingItemsBlock.contains(uuid) {
            return
        }
        ArchivedDropItem.unlockingItemsBlock.insert(uuid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ArchivedDropItem.unlockingItemsBlock.remove(self.uuid)
        }
        
        LocalAuth.attempt(label: label) { [weak self] success in
            if success {
                self?.needsUnlock = false
                completion(true)
            } else {
                self?.unlockWithPassword(from: from, label: label, action: action, completion: completion)
            }
        }
	}

	private func unlockWithPassword(from: UIViewController, label: String, action: String, completion: @escaping (Bool)->Void) {
		getPassword(from: from, title: label, action: action, requestHint: false, message: "Please enter the password you provided when locking this item.") { [weak self] password, hint in
			guard let password = password else {
				completion(false)
				return
			}
			if self?.lockPassword == sha1(password) {
				self?.needsUnlock = false
				completion(true)
			} else {
				genericAlert(title: "Wrong Password", message: "This password does not match the one you provided when locking this item.")
				completion(false)
			}
		}
	}

	var canOpen: Bool {
		let item = mostRelevantTypeItem?.objectForShare

		if item is MKMapItem {
			return true
		} else if item is CNContact {
			return true
		} else if let item = item as? URL {
			return !item.isFileURL && UIApplication.shared.canOpenURL(item)
		}

		return false
	}

	var watchItem: [String: Any] {
		var imageDate = updatedAt
		dataAccessQueue.sync {
			if let imagePath = imagePath, FileManager.default.fileExists(atPath: imagePath.path), let id = (try? imagePath.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
				imageDate = max(imageDate, id)
			}
		}
		return ["u": uuid.uuidString, "t": displayTitleOrUuid, "d": imageDate]
	}

	var canPreview: Bool {
		return typeItems.contains { $0.canPreview }
	}

	@discardableResult func tryPreview(in viewController: UIViewController, from cell: ArchivedItemCell?, preferChild childUuid: String? = nil) -> Bool {
		var itemToPreview: ArchivedDropItemType?
		if let childUuid = childUuid {
			itemToPreview = typeItems.first { $0.uuid.uuidString == childUuid }
		}
		itemToPreview = itemToPreview ?? previewableTypeItem

        guard let q = itemToPreview?.quickLook(in: viewController.view.window?.windowScene) else { return false }

		let n = PreviewHostingViewController(rootViewController: q)

		if !PersistedOptions.wideMode {
			n.sourceItemView = cell
		}

		if !PersistedOptions.fullScreenPreviews {
			n.modalPresentationStyle = .popover
		}
        
		viewController.present(n, animated: true)
		if let p = n.popoverPresentationController, let cell = cell {
			p.sourceView = cell
			p.sourceRect = cell.contentView.bounds.insetBy(dx: 6, dy: 6)
		}
		return true
	}

	@objc private func previewDismiss() {
		ViewController.top.dismiss(animated: true)
	}

	func tryOpen(in viewController: UINavigationController, completion: @escaping (Bool)->Void) {
		let item = mostRelevantTypeItem?.objectForShare
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
            UIApplication.shared.connectedScenes.first?.open(item, options: nil) { success in
				if !success {
					let message: String
					if item.isFileURL {
						message = "iOS does not recognise the type of this file"
					} else {
						message = "iOS does not recognise the type of this link"
					}
					genericAlert(title: "Can't Open", message: message)
				}
				completion(success)
			}
		} else {
			completion(false)
		}
	}
}
