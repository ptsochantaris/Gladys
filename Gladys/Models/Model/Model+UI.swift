
import CoreSpotlight
import WatchConnectivity
import CloudKit
import UIKit

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

			if let uuid = message["view"] as? String {
				ViewController.shared.highlightItem(with: uuid, andOpen: true)
				DispatchQueue.global().async {
					replyHandler([:])
				}
			}

			if let uuid = message["moveToTop"] as? String {
				if let item = Model.item(uuid: uuid) {
					ViewController.shared.sendToTop(item: item)
				}
				DispatchQueue.global().async {
					replyHandler([:])
				}
			}

			if let uuid = message["copy"] as? String {
				if let i = Model.item(uuid: uuid) {
					i.copyToPasteboard()
				}
				DispatchQueue.global().async {
					replyHandler([:])
				}
			}

			if let uuid = message["image"] as? String {
				if let i = Model.item(uuid: uuid) {
					let mode = i.displayMode
					let icon = i.displayIcon
					DispatchQueue.global().async {
						let W = message["width"] as! CGFloat
						let H = message["height"] as! CGFloat
						let size = CGSize(width: W, height: H)
						if mode == .center || mode == .circle {
							let scaledImage = icon.limited(to: size, limitTo: 0.2, singleScale: true)
							let data = scaledImage.pngData()!
							replyHandler(["image": data])
						} else {
							let scaledImage = icon.limited(to: size, limitTo: 1.0, singleScale: true)
							let data = scaledImage.jpegData(compressionQuality: 0.6)!
							replyHandler(["image": data])
						}
					}
				} else {
					DispatchQueue.global().async {
						replyHandler([:])
					}
				}
			}
		}
	}

	func updateContext() {
		let session = WCSession.default
		guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
		let bgTask = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
		DispatchQueue.global(qos: .background).async {
			do {
				let items = Model.threadSafeDrops.map { $0.watchItem }
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
			log("Starting save queue background task")
			saveBgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.gladys.saveTask", expirationHandler: nil)
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
				log("Ending save queue background task")
				UIApplication.shared.endBackgroundTask(b)
				saveBgTask = nil
			}
		}
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
