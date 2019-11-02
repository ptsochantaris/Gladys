
import CoreSpotlight
import WatchConnectivity
import CloudKit
import UIKit
import MapKit
import SafeUnarchiver

private class WatchDelegate: NSObject, WCSessionDelegate {

	override init() {
		super.init()
		let session = WCSession.default
		session.delegate = self
		session.activate()
	}

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		updateContext()
	}

	func sessionDidBecomeInactive(_ session: WCSession) {}

	func sessionDidDeactivate(_ session: WCSession) {}

	func sessionReachabilityDidChange(_ session: WCSession) {
		if session.isReachable && session.applicationContext.count == 0 && Model.drops.count > 0 {
			updateContext()
		}
	}

	func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
		DispatchQueue.main.async {
			self.handle(message: message, replyHandler: replyHandler)
		}
	}

	private func handle(message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {

		if let uuid = message["view"] as? String {
			ViewController.shared.highlightItem(with: uuid, andOpen: true)
			DispatchQueue.global(qos: .userInitiated).async {
				replyHandler([:])
			}

		} else if let uuid = message["moveToTop"] as? String, let item = Model.item(uuid: uuid) {
			ViewController.shared.sendToTop(item: item)
			DispatchQueue.global(qos: .userInitiated).async {
				replyHandler([:])
			}

		} else if let uuid = message["delete"] as? String, let item = Model.item(uuid: uuid) {
			ViewController.shared.deleteRequested(for: [item])
			DispatchQueue.global(qos: .userInitiated).async {
				replyHandler([:])
			}

		} else if let uuid = message["copy"] as? String, let item = Model.item(uuid: uuid) {
			item.copyToPasteboard()
			DispatchQueue.global(qos: .userInitiated).async {
				replyHandler([:])
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
			DispatchQueue.global(qos: .userInitiated).async {
				replyHandler([:])
			}
		}
	}

	private func handleMapItemPreview(mapItem: MKMapItem, size: CGSize, fallbackIcon: UIImage, replyHandler: @escaping ([String : Any]) -> Void) {
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

	private func proceedWithImage(_ icon: UIImage, size: CGSize?, mode: ArchivedDropItemDisplayType, replyHandler: @escaping ([String : Any]) -> Void) {
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
			replyHandler(["image": data])
		}
	}

	func updateContext() {
		let session = WCSession.default
		guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        BackgroundTask.registerForBackground()

		DispatchQueue.main.async {
			let total = Model.drops.count
			let items = Model.drops.prefix(100).map { $0.watchItem }
			DispatchQueue.global(qos: .background).async {
				if let compressedData = SafeArchiver.archive(items)?.data(operation: .compress) {
					do {
						try session.updateApplicationContext(["total": total, "dropList": compressedData])
						log("Updated watch context")
					} catch {
						log("Error updating watch context: \(error.localizedDescription)")
					}
				}
                BackgroundTask.unregisterForBackground()
			}
		}
	}
}

//////////////////////////////////////////////////////////

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
			//log("Starting save queue background task")
		}
		rebuildLabels()
	}

	static func startupComplete() {
		rebuildLabels()
		trimTemporaryDirectory()

		if WCSession.isSupported() {
			watchDelegate = WatchDelegate()
		}
	}

	static func saveComplete() {
		NotificationCenter.default.post(name: .SaveComplete, object: nil)
		if saveIsDueToSyncFetch {
			saveIsDueToSyncFetch = false
			log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
		} else {
			log("Will sync up after a local save")
			CloudManager.sync { error in
				if let error = error {
					log("Error in push after save: \(error.finalDescription)")
				}
			}
		}

		saveOverlap -= 1
		DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
			if saveOverlap == 0 {
				watchDelegate?.updateContext()
				if registeredForBackground {
					registeredForBackground = false
					BackgroundTask.unregisterForBackground()
					//log("Ending save queue background task")
				}
			}
		}
	}

	static func saveIndexComplete() {
		watchDelegate?.updateContext()
	}

	private static var foregroundObserver: NSObjectProtocol?
	private static var backgroundObserver: NSObjectProtocol?

	static func beginMonitoringChanges() {
		let n = NotificationCenter.default
		foregroundObserver = n.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: OperationQueue.main) { _ in
			foregrounded()
		}
		backgroundObserver = n.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: OperationQueue.main) { _ in
			backgrounded()
		}
		foregrounded()
	}

	static func doneMonitoringChanges() {
		let n = NotificationCenter.default
		if let foregroundObserver = foregroundObserver {
			n.removeObserver(foregroundObserver)
		}
		if let backgroundObserver = backgroundObserver {
			n.removeObserver(backgroundObserver)
		}
	}

	private static let filePresenter = ModelFilePresenter()
	
	private static func foregrounded() {
		NSFileCoordinator.addFilePresenter(filePresenter)
		reloadDataIfNeeded()
	}

	private static func backgrounded() {
		NSFileCoordinator.removeFilePresenter(filePresenter)
	}
    
    static func createMirror(completion: @escaping ()->Void) {
        log("Creating file mirror")
        drops.forEach { $0.skipMirrorAtNextSave = false }
        runMirror(completion: completion)
    }

    static func updateMirror(completion: @escaping ()->Void) {
        log("Updating file mirror")
        runMirror(completion: completion)
    }

    private static func runMirror(completion: @escaping ()->Void) {
        let itemsToMirror = drops.filter { $0.goodToSave }
        MirrorManager.mirrorToFiles(from: itemsToMirror, completion: completion)
    }
    
    static func scanForMirrorChanges(completion: @escaping ()->Void) {
        let itemsToMirror = drops.filter { $0.goodToSave }
        MirrorManager.scanForMirrorChanges(items: itemsToMirror, completion: completion)
    }
    
    static func deleteMirror(completion: @escaping ()->Void) {
        log("Deleting file mirror")
        MirrorManager.removeMirrorIfNeeded(completion: completion)
    }
}
