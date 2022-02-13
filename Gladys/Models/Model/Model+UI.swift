import CoreSpotlight
import WatchConnectivity
import CloudKit
import UIKit
import MapKit
import GladysFramework

private class WatchDelegate: NSObject, WCSessionDelegate {

	override init() {
		super.init()
		let session = WCSession.default
		session.delegate = self
		session.activate()
	}

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    
	func sessionReachabilityDidChange(_ session: WCSession) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}
    
    func sessionDidDeactivate(_ session: WCSession) {}
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.handle(message: message, replyHandler: { _ in })
        }
    }
    
	func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
		DispatchQueue.main.async {
			self.handle(message: message, replyHandler: replyHandler)
		}
	}

	private func handle(message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {

		if let uuid = message["view"] as? String {
            let request = HighlightRequest(uuid: uuid, open: true)
            NotificationCenter.default.post(name: .HighlightItemRequested, object: request)
			DispatchQueue.global(qos: .background).async {
				replyHandler([:])
			}

		} else if let uuid = message["moveToTop"] as? String, let item = Model.item(uuid: uuid) {
            Model.sendToTop(items: [item])
			DispatchQueue.global(qos: .background).async {
				replyHandler([:])
			}

		} else if let uuid = message["delete"] as? String, let item = Model.item(uuid: uuid) {
            Model.delete(items: [item])
			DispatchQueue.global(qos: .background).async {
				replyHandler([:])
			}

		} else if let uuid = message["copy"] as? String, let item = Model.item(uuid: uuid) {
			item.copyToPasteboard()
			DispatchQueue.global(qos: .background).async {
				replyHandler([:])
			}

        } else if let command = message["update"] as? String, command == "full" {
            buildContext { context in
                replyHandler(context ?? [:])
            }

		} else if let uuid = message["image"] as? String, let item = Model.item(uuid: uuid) {

			let W = message["width"] as! CGFloat
			let H = message["height"] as! CGFloat
			let size = CGSize(width: W, height: H)

			let mode = item.displayMode
			if mode == .center, let backgroundInfoObject = item.backgroundInfoObject {
				if let color = backgroundInfoObject as? UIColor {
					let icon = UIGraphicsImageRenderer.init(size: size).image { context in
						context.cgContext.setFillColor(color.cgColor)
						context.fill(CGRect(origin: .zero, size: size))
					}
					proceedWithImage(icon, size: nil, mode: .center, replyHandler: replyHandler)

				} else if let mapItem = backgroundInfoObject as? MKMapItem {
					handleMapItemPreview(mapItem: mapItem, size: size, fallbackIcon: item.displayIcon, replyHandler: replyHandler)

				} else {
					proceedWithImage(item.displayIcon, size: size, mode: .center, replyHandler: replyHandler)
				}
			} else {
				proceedWithImage(item.displayIcon, size: size, mode: mode, replyHandler: replyHandler)
			}

		} else {
			DispatchQueue.global(qos: .background).async {
				replyHandler([:])
			}
		}
	}

	private func handleMapItemPreview(mapItem: MKMapItem, size: CGSize, fallbackIcon: UIImage, replyHandler: @escaping ([String: Any]) -> Void) {
		let O = MKMapSnapshotter.Options()
		O.region = MKCoordinateRegion(center: mapItem.placemark.coordinate, latitudinalMeters: 150.0, longitudinalMeters: 150.0)
		O.size = size
		O.showsBuildings = true
        O.pointOfInterestFilter = .includingAll
		let S = MKMapSnapshotter(options: O)
		S.start { snapshot, error in
			if let error = error {
				log("Error taking map snapshot: \(error.finalDescription)")
			}
			if let snapshot = snapshot {
				self.proceedWithImage(snapshot.image, size: size, mode: .fill, replyHandler: replyHandler)
			} else {
				self.proceedWithImage(fallbackIcon, size: size, mode: .center, replyHandler: replyHandler)
			}
		}
	}

	private func proceedWithImage(_ icon: UIImage, size: CGSize?, mode: ArchivedDropItemDisplayType, replyHandler: @escaping ([String: Any]) -> Void) {
		imageProcessingQueue.async {
			let data: Data
			if let size = size {
				if mode == .center || mode == .circle {
					let scaledImage = icon.limited(to: size, limitTo: 0.2, singleScale: true)
					data = scaledImage.pngData()!
				} else {
					let scaledImage = icon.limited(to: size, limitTo: 1.0, singleScale: true)
					data = scaledImage.jpegData(compressionQuality: 0.6)!
				}
			} else {
				data = icon.pngData()!
			}
            DispatchQueue.global(qos: .default).async {
                replyHandler(["image": data])
            }
		}
	}

    fileprivate func buildContext(completion: @escaping ([String: Any]?) -> Void) {
        BackgroundTask.registerForBackground()

        DispatchQueue.main.async {
            let total = Model.drops.count
            let items = Model.drops.prefix(100).map { $0.watchItem }
            DispatchQueue.global(qos: .background).async {
                if let compressedData = SafeArchiving.archive(items)?.data(operation: .compress) {
                    log("Built watch context")
                    completion(["total": total, "dropList": compressedData])
                } else {
                    log("Failed to build watch context")
                    completion(nil)
                }
                BackgroundTask.unregisterForBackground()
            }
        }
    }

	fileprivate func updateContext() {
		let session = WCSession.default
        guard session.isReachable, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        buildContext { context in
            if let context = context {
                session.transferUserInfo(context)
                log("Updated watch context")
            }
        }
	}
}

extension Model.SortOption {
    var ascendingIcon: UIImage? {
        switch self {
        case .label: return UIImage(systemName: "line.horizontal.3")
        case .dateAdded: return UIImage(systemName: "calendar")
        case .dateModified: return UIImage(systemName: "calendar.badge.exclamationmark")
        case .note: return UIImage(systemName: "rectangle.and.pencil.and.ellipsis")
        case .title: return UIImage(systemName: "arrow.down")
        case .size: return UIImage(systemName: "arrow.up.left.and.arrow.down.right.circle")
        }
    }
    var descendingIcon: UIImage? {
        switch self {
        case .label: return UIImage(systemName: "line.horizontal.3")
        case .dateAdded: return UIImage(systemName: "calendar")
        case .dateModified: return UIImage(systemName: "calendar.badge.exclamationmark")
        case .note: return UIImage(systemName: "rectangle.and.pencil.and.ellipsis")
        case .title: return UIImage(systemName: "arrow.up")
        case .size: return UIImage(systemName: "arrow.down.forward.and.arrow.up.backward.circle")
        }
    }
}

extension UISceneSession {
    var associatedFilter: Filter {
        if let existing = userInfo?[kGladysMainFilter] as? Filter {
            return existing
        }
        let newFilter = Filter()
        if userInfo == nil {
            userInfo = [String: Any]()
        }
        userInfo![kGladysMainFilter] = newFilter
        return newFilter
    }
}

extension UIView {
    var associatedFilter: Filter? {
        let w = (self as? UIWindow) ?? window
        return w?.windowScene?.session.associatedFilter
    }
}

extension Model {

	private static var saveOverlap = 0
	private static var registeredForBackground = false

	private static var watchDelegate: WatchDelegate?
	
	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: filePresenter)
	}

	static func prepareToSave() {
		saveOverlap += 1
		if !registeredForBackground {
			registeredForBackground = true
			BackgroundTask.registerForBackground()
			// log("Starting save queue background task")
		}
	}

	static func startupComplete() {
		trimTemporaryDirectory()

		if WCSession.isSupported() {
			watchDelegate = WatchDelegate()
		}
	}

    static func saveComplete(wasIndexOnly: Bool) {
        if wasIndexOnly {
            saveDone()
        } else {
            saveOverlap -= 1
            if saveOverlap == 0 {
                if PersistedOptions.mirrorFilesToDocuments {
                    updateMirror {
                        saveDone()
                    }
                } else {
                    saveDone()
                }
            }
        }
	}
    
    private static func saveDone() {
        watchDelegate?.updateContext()
        
        if saveIsDueToSyncFetch && !CloudManager.syncDirty {
            saveIsDueToSyncFetch = false
            log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
        } else {
            if CloudManager.syncDirty {
                log("A sync had been requested while syncing, evaluating another sync")
            }
            CloudManager.syncAfterSaveIfNeeded()
        }
        
        if registeredForBackground {
            registeredForBackground = false
            BackgroundTask.unregisterForBackground()
        }
    }

	private static var foregroundObserver: NSObjectProtocol?
	private static var backgroundObserver: NSObjectProtocol?

	static func beginMonitoringChanges() {
		let n = NotificationCenter.default
		foregroundObserver = n.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
			foregrounded()
		}
		backgroundObserver = n.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
			backgrounded()
		}
        foregrounded()
	}

	private static let filePresenter = ModelFilePresenter()
	
	private static func foregrounded() {
		NSFileCoordinator.addFilePresenter(filePresenter)
		reloadDataIfNeeded()
	}

	private static func backgrounded() {
		NSFileCoordinator.removeFilePresenter(filePresenter)
	}
    
    static func createMirror(completion: @escaping () -> Void) {
        log("Creating file mirror")
        drops.forEach { $0.flags.remove(.skipMirrorAtNextSave) }
        runMirror(completion: completion)
    }

    static func updateMirror(completion: @escaping () -> Void) {
        log("Updating file mirror")
        runMirror(completion: completion)
    }

    private static func runMirror(completion: @escaping () -> Void) {
        let itemsToMirror: ContiguousArray = drops.filter { $0.goodToSave }
        BackgroundTask.registerForBackground()
        MirrorManager.mirrorToFiles(from: itemsToMirror, andPruneOthers: true) {
            completion()
            BackgroundTask.unregisterForBackground()
        }
    }
    
    static func scanForMirrorChanges(completion: @escaping () -> Void) {
        BackgroundTask.registerForBackground()
        let itemsToMirror: ContiguousArray = drops.filter { $0.goodToSave }
        MirrorManager.scanForMirrorChanges(items: itemsToMirror) {
            completion()
            BackgroundTask.unregisterForBackground()
        }
    }
    
    static func deleteMirror(completion: @escaping () -> Void) {
        MirrorManager.removeMirrorIfNeeded(completion: completion)
    }
    
    static func _updateBadge() {
        if PersistedOptions.badgeIconWithItemCount, let count = lastUsedWindow?.associatedFilter?.filteredDrops.count {
            log("Updating app badge to show item count (\(count))")
            UIApplication.shared.applicationIconBadgeNumber = count
        } else {
            log("Updating app badge to clear")
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
}
