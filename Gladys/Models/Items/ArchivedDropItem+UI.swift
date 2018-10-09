
import UIKit
import MapKit
import CloudKit
import Contacts
import ContactsUI
import CoreSpotlight
import MobileCoreServices
import LocalAuthentication
import GladysFramework

class QLHostingViewController: UINavigationController {
	var relatedItem: ArchivedDropItem?
	var relatedChildItem: ArchivedDropItemType?

	override func viewDidLoad() {
		super.viewDidLoad()
		preferredContentSize = mainWindow.bounds.size
		let tint = ViewController.tintColor
		view.tintColor = tint
		navigationBar.tintColor = tint
		if let sourceBar = ViewController.shared.navigationController?.navigationBar {
			navigationBar.titleTextAttributes = sourceBar.titleTextAttributes
			navigationBar.barTintColor = sourceBar.barTintColor
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if relatedItem != nil {
			userActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
		}
	}
	override func updateUserActivityState(_ activity: NSUserActivity) {
		super.updateUserActivityState(activity)
		if let relatedItem = relatedItem {
			ArchivedDropItem.updateUserActivity(activity, from: relatedItem, child: relatedChildItem, titled: "Quick look")
		}
	}
	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		viewControllers = []
	}
}

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
		a.addAction(UIAlertAction(title: action, style: .default, handler: { [weak self] ac in

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
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { ac in
			completion(nil, nil)
		}))
		from.present(a, animated: true)
	}

	func lock(from: UIViewController, completion: @escaping (Data?, String?)->Void) {
		let auth = LAContext()
		var authError: NSError?
		let message: String
		if auth.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
			message = "Please provide a backup password in case Touch or Face ID fails. You can also provide an optional label to display while the item is locked."
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

	func unlock(from: UIViewController, label: String, action: String, completion: @escaping (Bool)->Void) {
		let auth = LAContext()
		var authError: NSError?
		if auth.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
			auth.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: label, reply: { success, error in
				DispatchQueue.main.async { [weak self] in
					if success {
						self?.needsUnlock = false
						completion(true)
					} else {
						self?.unlockWithPassword(from: from, label: label, action: action, completion: completion)
					}
				}
			})
		} else {
			unlockWithPassword(from: from, label: label, action: action, completion: completion)
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

	func tryPreview(in viewController: UIViewController, from: ArchivedItemCell?, preferChild childUuid: String? = nil) {
		var itemToPreview: ArchivedDropItemType?
		if let childUuid = childUuid {
			itemToPreview = typeItems.first { $0.uuid.uuidString == childUuid }
		}
		itemToPreview = itemToPreview ?? previewableTypeItem
		guard let q = itemToPreview?.quickLook(extraRightButton: nil) else { return }
		let n = QLHostingViewController(rootViewController: q)
		n.relatedItem = self

		if PersistedOptions.fullScreenPreviews {
			let r = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(previewDismiss))
			q.navigationItem.rightBarButtonItem = r
		} else {
			n.modalPresentationStyle = .popover
			if ViewController.shared.phoneMode || UIAccessibility.isVoiceOverRunning {
				let r = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(previewDone))
				q.navigationItem.rightBarButtonItem = r
			}
		}
		viewController.present(n, animated: true)
		if let p = q.popoverPresentationController, let from = from {
			p.sourceView = from
			p.sourceRect = from.contentView.bounds.insetBy(dx: 6, dy: 6)
		}
	}

	@objc private func previewDismiss() {
		ViewController.top.dismiss(animated: true)
	}

	@objc private func previewDone() {
		ViewController.shared.dismissAnyPopOver()
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
			UIApplication.shared.open(item, options: [:]) { success in
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
		}
	}
}
