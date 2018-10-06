
import CoreSpotlight
import WatchConnectivity
import CloudKit
import UIKit
import MapKit

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
		O.showsPointsOfInterest = true
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
		let bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
		DispatchQueue.global(qos: .background).async {
			var items = [[String:Any]]()
			DispatchQueue.main.sync {
				items = Model.drops.map { $0.watchItem }
			}
			do {
				let compressedData = NSKeyedArchiver.archivedData(withRootObject: items).data(operation: .compress)!
				try session.updateApplicationContext(["dropList": compressedData])
				log("Updated watch context")
			} catch {
				log("Error updating watch context: \(error.localizedDescription)")
			}
			UIApplication.shared.endBackgroundTask(bgTask)
		}
	}
}

//////////////////////////////////////////////////////////

extension Model {

	private static var saveOverlap = 0
	private static var saveBgTask: UIBackgroundTaskIdentifier?

	private static var watchDelegate: WatchDelegate?
	
	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: filePresenter)
	}

	static func prepareToSave() {
		saveOverlap += 1
		if saveBgTask == nil {
			//log("Starting save queue background task")
			saveBgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.Gladys.saveTask", expirationHandler: nil)
		}
		rebuildLabels()
	}

	static func startupComplete() {

		// cleanup, in case of previous crashes, cancelled transfers, etc

		let fm = FileManager.default
		guard let items = try? fm.contentsOfDirectory(at: appStorageUrl, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants) else { return }
		let uuids = items.compactMap { UUID(uuidString: $0.lastPathComponent) }
		let nonExistingUUIDs = uuids.filter { uuid -> Bool in
			return !drops.contains { $0.uuid == uuid }
		}
		for uuid in nonExistingUUIDs {
			let url = appStorageUrl.appendingPathComponent(uuid.uuidString)
			try? fm.removeItem(at: url)
		}

		rebuildLabels()

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
			if saveOverlap == 0, let b = saveBgTask {
				watchDelegate?.updateContext()
				//log("Ending save queue background task")
				UIApplication.shared.endBackgroundTask(b)
				saveBgTask = nil
			}
		}
	}

	static func saveIndexComplete() {
		watchDelegate?.updateContext()
	}
	
	static func beginMonitoringChanges() {
		let n = NotificationCenter.default
		n.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: OperationQueue.main) { _ in
			foregrounded()
		}
		n.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: OperationQueue.main) { _ in
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
}
