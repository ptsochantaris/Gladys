import CloudKit
import Contacts
import ContactsUI
import CoreSpotlight
import GladysCommon
import GladysUI
import MapKit
import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

extension Filter.Toggle.Function {
    var dragItem: UIDragItem? {
        let p = NSItemProvider(item: displayText as NSSecureCoding, typeIdentifier: UTType.plainText.identifier)
        p.registerObject(userActivity, visibility: .all)

        let i = UIDragItem(itemProvider: p)
        i.localObject = self
        return i
    }

    private var userActivity: NSUserActivity {
        let activity = NSUserActivity(activityType: kGladysMainListActivity)
        activity.title = displayText
        let section = Filter.Toggle(function: self, count: 0, active: true, currentDisplayMode: .scrolling, preferredDisplayMode: .scrolling)
        if let data = try? JSONEncoder().encode([section]) {
            activity.addUserInfoEntries(from: [kGladysMainViewSections: data])
        }
        return activity
    }

    @MainActor
    func openInWindow(from scene: UIScene) {
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = scene

        let text = displayText
        let suggestedLabelSession = UIApplication.shared.openSessions.first {
            if let f = ($0.userInfo?[kGladysMainFilter] as? Filter) {
                return f.enabledLabelsForTitles == [text]
            } else {
                return false
            }
        }

        UIApplication.shared.requestSceneSessionActivation(suggestedLabelSession, userActivity: userActivity, options: options) { error in
            log("Error opening new window: \(error.localizedDescription)")
        }
    }
}

extension ArchivedItem {
    func dragItem(forLabelIndex index: Int) -> UIDragItem? {
        guard index < labels.count else {
            return nil
        }
        let text = labels[index]
        return Filter.Toggle.Function.userLabel(text).dragItem
    }

    @MainActor
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

    @MainActor
    func lock(completion: @escaping (Data?, String?) -> Void) {
        let message: String
        if LocalAuth.canUseLocalAuth {
            message = "Please provide a backup password in case TouchID or FaceID fails. You can also provide an optional label to display while the item is locked."
        } else {
            message = "Please provide the password you will use to unlock this item. You can also provide an optional label to display while the item is locked."
        }
        getPassword(title: "Lock Item", action: "Lock", requestHint: true, message: message) { [weak self] password, hint in
            guard let password else {
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
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1000 * NSEC_PER_MSEC)
            ArchivedItem.unlockingItemsBlock.remove(uuid)
        }

        LocalAuth.attempt(label: label) { [weak self] success in
            if success {
                self?.flags.remove(.needsUnlock)
                completion(true)
            } else {
                Task { @MainActor [weak self] in
                    self?.unlockWithPassword(label: label, action: action, completion: completion)
                }
            }
        }
    }

    @MainActor
    private func unlockWithPassword(label: String, action: String, completion: @escaping (Bool) -> Void) {
        getPassword(title: label, action: action, requestHint: false, message: "Please enter the password you provided when locking this item.") { [weak self] password, _ in
            guard let password else {
                completion(false)
                return
            }
            if self?.lockPassword == sha1(password) {
                self?.flags.remove(.needsUnlock)
                completion(true)
            } else {
                Task {
                    await genericAlert(title: "Wrong Password", message: "This password does not match the one you provided when locking this item.")
                    completion(false)
                }
            }
        }
    }

    var canOpen: Bool {
        mostRelevantTypeItem?.canOpen == true
    }

    var watchItem: [String: Any] {
        var imageDate = updatedAt
        componentAccessQueue.sync {
            if let imagePath, FileManager.default.fileExists(atPath: imagePath.path), let id = (try? imagePath.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                imageDate = max(imageDate, id)
            }
        }
        return ["u": uuid.uuidString, "t": displayTitleOrUuid, "d": imageDate]
    }

    @MainActor
    @discardableResult func tryPreview(in viewController: UIViewController, from cell: ArchivedItemCell?, preferChild childUuid: String? = nil, forceFullscreen: Bool = false) -> Bool {
        var itemToPreview: Component?
        if let childUuid {
            itemToPreview = components.first { $0.uuid.uuidString == childUuid }
        }
        itemToPreview = itemToPreview ?? previewableTypeItem

        guard let ql = itemToPreview?.quickLook() else { return false }

        let goFullscreen = PersistedOptions.fullScreenPreviews || forceFullscreen || UIDevice.current.userInterfaceIdiom == .phone

        if goFullscreen {
            let nav = GladysNavController(rootViewController: ql)
            nav.modalPresentationStyle = .overFullScreen
            if !PersistedOptions.wideMode {
                nav.sourceItemView = cell
            }
            viewController.present(nav, animated: true)

        } else {
            let n = GladysNavController(rootViewController: ql)
            n.modalPresentationStyle = .popover
            if let p = n.popoverPresentationController, let cell {
                p.sourceView = cell
                p.sourceRect = cell.contentView.bounds.insetBy(dx: 6, dy: 6)
                p.popoverBackgroundViewClass = GladysPopoverBackgroundView.self
            }
            viewController.present(n, animated: true)
            if let p = n.popoverPresentationController, let cell, p.sourceView == nil { // sanity check, iOS versions get confused about this
                p.sourceView = cell
                p.sourceRect = cell.contentView.bounds.insetBy(dx: 6, dy: 6)
                p.popoverBackgroundViewClass = GladysPopoverBackgroundView.self
            }
        }

        return true
    }

    @MainActor
    func tryOpen(in viewController: UINavigationController?, completion: @escaping (Bool) -> Void) {
        let item = mostRelevantTypeItem?.objectForShare
        if let item = item as? MKMapItem {
            item.openInMaps(launchOptions: [:])
            completion(true)
        } else if let contact = item as? CNContact {
            let c = CNContactViewController(forUnknownContact: contact)
            c.contactStore = CNContactStore()
            c.hidesBottomBarWhenPushed = true
            if let viewController {
                viewController.pushViewController(c, animated: true)
            } else {
                let scene = currentWindow?.windowScene
                let request = UIRequest(vc: c, sourceView: nil, sourceRect: nil, sourceButton: nil, pushInsteadOfPresent: true, sourceScene: scene)
                sendNotification(name: .UIRequest, object: request)
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
                    Task {
                        await genericAlert(title: "Can't Open", message: message)
                    }
                }
                completion(success)
            }
        } else {
            completion(false)
        }
    }
}
