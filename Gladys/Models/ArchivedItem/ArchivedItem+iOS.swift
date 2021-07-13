import UIKit
import MapKit
import CloudKit
import Contacts
import ContactsUI
import CoreSpotlight
import MobileCoreServices
import GladysFramework

extension String {
    var labelDragItem: UIDragItem? {
        let p = NSItemProvider(item: self as NSSecureCoding, typeIdentifier: kUTTypePlainText as String)
        p.registerObject(labelActivity, visibility: .all)
        
        let i = UIDragItem(itemProvider: p)
        i.localObject = self
        return i
    }
    
    private var labelActivity: NSUserActivity {
        let activity = NSUserActivity(activityType: kGladysMainListActivity)
        activity.title = self
        let section = ModelFilterContext.LabelToggle(name: self, count: 0, enabled: true, displayMode: .scrolling, preferredDisplayMode: .scrolling, emptyChecker: false)
        if let data = try? JSONEncoder().encode([section]) {
            activity.addUserInfoEntries(from: [kGladysMainViewSections: data])
        }
        return activity
    }
    
    private var suggestedLabelSession: UISceneSession? {
        return UIApplication.shared.openSessions.first {
            if let f = ($0.userInfo?[kGladysMainFilter] as? ModelFilterContext) {
                return f.enabledLabelsForTitles == [self]
            } else {
                return false
            }
        }
    }
    
    func openInWindow(from scene: UIScene?) {
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = scene
        UIApplication.shared.requestSceneSessionActivation(suggestedLabelSession, userActivity: labelActivity, options: options) { error in
            log("Error opening new window: \(error.localizedDescription)")
        }
    }
}

extension ArchivedItem {

	func dragItem(forLabelIndex index: Int) -> UIDragItem? {
		guard index < labels.count else {
			return nil
		}

        return labels[index].labelDragItem
	}

	private func getPassword(title: String, action: String, requestHint: Bool, message: String, completion: @escaping (String?, String?) -> Void) {
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
		a.addAction(UIAlertAction(title: action, style: .default) { [weak self] _ in

			var hint: String?
			if a.textFields!.count > 1 {
				hint = a.textFields![1].text
			}

			let password = a.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			if password.isEmpty {
				self?.getPassword(title: title, action: action, requestHint: requestHint, message: message, completion: completion)
			} else {
				completion(password, hint)
			}
		})
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
			completion(nil, nil)
		})
        currentWindow?.alertPresenter?.present(a, animated: true)
	}

	func lock(completion: @escaping (Data?, String?) -> Void) {
		let message: String
        if LocalAuth.canUseLocalAuth {
			message = "Please provide a backup password in case TouchID or FaceID fails. You can also provide an optional label to display while the item is locked."
		} else {
			message = "Please provide the password you will use to unlock this item. You can also provide an optional label to display while the item is locked."
		}
		getPassword(title: "Lock Item", action: "Lock", requestHint: true, message: message) { [weak self] password, hint in
			guard let password = password else {
				completion(nil, nil)
				return
			}
            self?.flags.insert(.needsUnlock)
			completion(sha1(password), hint)
		}
	}

    private static var unlockingItemsBlock = Set<UUID>()
	func unlock(label: String, action: String, completion: @escaping (Bool) -> Void) {
        if ArchivedItem.unlockingItemsBlock.contains(uuid) {
            return
        }
        ArchivedItem.unlockingItemsBlock.insert(uuid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ArchivedItem.unlockingItemsBlock.remove(self.uuid)
        }
        
        LocalAuth.attempt(label: label) { [weak self] success in
            if success {
                self?.flags.remove(.needsUnlock)
                completion(true)
            } else {
                self?.unlockWithPassword(label: label, action: action, completion: completion)
            }
        }
	}

	private func unlockWithPassword(label: String, action: String, completion: @escaping (Bool) -> Void) {
		getPassword(title: label, action: action, requestHint: false, message: "Please enter the password you provided when locking this item.") { [weak self] password, _ in
			guard let password = password else {
				completion(false)
				return
			}
			if self?.lockPassword == sha1(password) {
                self?.flags.remove(.needsUnlock)
				completion(true)
			} else {
				genericAlert(title: "Wrong Password", message: "This password does not match the one you provided when locking this item.")
				completion(false)
			}
		}
	}

	var canOpen: Bool {
        return mostRelevantTypeItem?.canOpen == true
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
		return components.contains { $0.canPreview }
	}

    @discardableResult func tryPreview(in viewController: UIViewController, from cell: ArchivedItemCell?, preferChild childUuid: String? = nil, forceFullscreen: Bool = false) -> Bool {
		var itemToPreview: Component?
		if let childUuid = childUuid {
			itemToPreview = components.first { $0.uuid.uuidString == childUuid }
		}
		itemToPreview = itemToPreview ?? previewableTypeItem

        guard let ql = itemToPreview?.quickLook() else { return false }

		if !PersistedOptions.wideMode {
			ql.sourceItemView = cell
		}
        
        let goFullscreen = PersistedOptions.fullScreenPreviews || forceFullscreen || UIDevice.current.userInterfaceIdiom == .phone
        
        if goFullscreen {
            viewController.present(ql, animated: true)

        } else {
            let n = GladysNavController(rootViewController: ql)
            n.modalPresentationStyle = .popover
            if let p = n.popoverPresentationController, let cell = cell {
                p.sourceView = cell
                p.sourceRect = cell.contentView.bounds.insetBy(dx: 6, dy: 6)
                p.popoverBackgroundViewClass = GladysPopoverBackgroundView.self
            }
            viewController.present(n, animated: true)
            if let p = n.popoverPresentationController, let cell = cell, p.sourceView == nil { // sanity check, iOS versions get confused about this
                p.sourceView = cell
                p.sourceRect = cell.contentView.bounds.insetBy(dx: 6, dy: 6)
                p.popoverBackgroundViewClass = GladysPopoverBackgroundView.self
            }
        }
        
		return true
	}
    
	func tryOpen(in viewController: UINavigationController?, completion: @escaping (Bool) -> Void) {
		let item = mostRelevantTypeItem?.objectForShare
		if let item = item as? MKMapItem {
			item.openInMaps(launchOptions: [:])
			completion(true)
		} else if let contact = item as? CNContact {
			let c = CNContactViewController(forUnknownContact: contact)
			c.contactStore = CNContactStore()
			c.hidesBottomBarWhenPushed = true
            if let viewController = viewController {
                viewController.pushViewController(c, animated: true)
            } else {
                let scene = currentWindow?.windowScene
                let request = UIRequest(vc: c, sourceView: nil, sourceRect: nil, sourceButton: nil, pushInsteadOfPresent: true, sourceScene: scene)
                NotificationCenter.default.post(name: .UIRequest, object: request)
            }
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
