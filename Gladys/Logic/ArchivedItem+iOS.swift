import Contacts
import ContactsUI
import GladysCommon
import GladysUI
import GladysUIKit
import MapKit
import UIKit
import UniformTypeIdentifiers

extension Filter.Toggle.Function {
    @MainActor
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
                f.enabledLabelsForTitles == [text]
            } else {
                false
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

    private func getPassword(title: String, action: String, requestHint: Bool, message: String, completion: @escaping (String?, String?) -> Void) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addTextField { textField in
            textField.placeholder = "Password"
            textField.isSecureTextEntry = true
        }
        if requestHint {
            a.addTextField { [weak self] textField in
                guard let self else { return }
                textField.placeholder = "Label when locked"
                textField.text = displayText.0
            }
        }
        a.addAction(UIAlertAction(title: action, style: .default) { [weak self] _ in
            var hint: String?
            if a.textFields!.count > 1 {
                hint = a.textFields![1].text
            }

            let password = a.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let self, password.isEmpty {
                getPassword(title: title, action: action, requestHint: requestHint, message: message, completion: completion)
            } else {
                completion(password, hint)
            }
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(nil, nil)
        })
        currentWindow?.alertPresenter?.present(a, animated: true)
    }

    func lock() async -> (Data?, String?) {
        let message = if LocalAuth.canUseLocalAuth {
            "Please provide a backup password in case TouchID or FaceID fails. You can also provide an optional label to display while the item is locked."
        } else {
            "Please provide the password you will use to unlock this item. You can also provide an optional label to display while the item is locked."
        }
        return await withCheckedContinuation { continuation in
            getPassword(title: "Lock Item", action: "Lock", requestHint: true, message: message) { [weak self] password, hint in
                guard let password else {
                    continuation.resume(returning: (nil, nil))
                    return
                }
                self?.flags.insert(.needsUnlock)
                continuation.resume(returning: (sha1(password), hint))
            }
        }
    }

    private static var unlockingItemsBlock = Set<UUID>()
    func unlock(label: String, action: String) async -> Bool? {
        if ArchivedItem.unlockingItemsBlock.contains(uuid) {
            return nil
        }

        ArchivedItem.unlockingItemsBlock.insert(uuid)
        Task {
            try? await Task.sleep(nanoseconds: 1000 * NSEC_PER_MSEC)
            ArchivedItem.unlockingItemsBlock.remove(uuid)
        }

        if let success = await LocalAuth.attempt(label: label) {
            if success {
                flags.remove(.needsUnlock)
                return true
            } else {
                return await unlockWithPassword(label: label, action: action)
            }
        }

        return nil
    }

    private func unlockWithPassword(label: String, action: String) async -> Bool {
        await withCheckedContinuation { continuation in
            getPassword(title: label, action: action, requestHint: false, message: "Please enter the password you provided when locking this item.") { [weak self] password, _ in
                guard let password else {
                    continuation.resume(returning: false)
                    return
                }
                if self?.lockPassword == sha1(password) {
                    self?.flags.remove(.needsUnlock)
                    continuation.resume(returning: true)
                } else {
                    Task {
                        await genericAlert(title: "Wrong Password", message: "This password does not match the one you provided when locking this item.")
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    var canOpen: Bool {
        mostRelevantTypeItem?.canOpen == true
    }

    var watchItem: WatchMessage.DropInfo {
        var imageDate = updatedAt
        if let imagePath, FileManager.default.fileExists(atPath: imagePath.path), let id = (try? imagePath.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
            imageDate = max(imageDate, id)
        }
        return WatchMessage.DropInfo(id: uuid.uuidString, title: displayTitleOrUuid, imageDate: imageDate)
    }

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
                #if !os(visionOS)
                    p.popoverBackgroundViewClass = GladysPopoverBackgroundView.self
                #endif
            }
            viewController.present(n, animated: true)
            if let p = n.popoverPresentationController, let cell, p.sourceView == nil { // sanity check, iOS versions get confused about this
                p.sourceView = cell
                p.sourceRect = cell.contentView.bounds.insetBy(dx: 6, dy: 6)
                #if !os(visionOS)
                    p.popoverBackgroundViewClass = GladysPopoverBackgroundView.self
                #endif
            }
        }

        return true
    }

    @discardableResult
    func tryOpen(in viewController: UINavigationController?) async -> Bool {
        let item = mostRelevantTypeItem?.objectForShare
        if let item = item as? MKMapItem {
            item.openInMaps(launchOptions: [:])
            return true
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
            return false
        } else if let item = item as? URL {
            guard let firstScene = UIApplication.shared.connectedScenes.first else {
                return false
            }

            let success = await firstScene.open(item, options: nil)
            if !success {
                let message = if item.isFileURL {
                    "iOS does not recognise the type of this file"
                } else {
                    "iOS does not recognise the type of this link"
                }
                await genericAlert(title: "Can't Open", message: message)
            }
            return success
        } else {
            return false
        }
    }
}
