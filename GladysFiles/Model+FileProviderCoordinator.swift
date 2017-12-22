import Foundation
import FileProvider

extension Model {

	private class ModelFilePresenter: NSObject, NSFilePresenter {

		var presentedItemURL: URL? {
			return Model.itemsDirectoryUrl
		}

		var presentedItemOperationQueue: OperationQueue {
			return accessQueue
		}

		func presentedItemDidChange() {
			accessQueue.addOperation {
				reloadDataIfNeeded()
			}
		}
	}

	private static let fileExtensionPresenter = ModelFilePresenter()
	static let accessQueue: OperationQueue = {
		let o = OperationQueue()
		o.maxConcurrentOperationCount = 1
		o.qualityOfService = .background
		return o
	}()

	static var coordinator: NSFileCoordinator {
		let coordinator = NSFileCoordinator(filePresenter: nil)
		coordinator.purposeIdentifier = NSFileProviderManager.default.providerIdentifier
		return coordinator
	}

	static func prepareToSave() {}
	static func saveComplete() {}

	static func startupComplete() {
		NSFileCoordinator.addFilePresenter(fileExtensionPresenter)
	}

	static func signalRootChange() {
		NSFileProviderManager.default.signalEnumerator(for: .rootContainer) { error in
			if let e = error {
				log("Error signalling: \(e.finalDescription)")
			}
		}
	}

	static func signalWorkingSetChange() {
		NSFileProviderManager.default.signalEnumerator(for: .workingSet) { error in
			if let e = error {
				log("Error signalling: \(e.finalDescription)")
			}
		}
	}

	static func reloadCompleted() {
		Model.signalRootChange()
		Model.signalWorkingSetChange()
	}

	static var nonDeletedDrops: [ArchivedDropItem] {
		return drops.filter { !$0.needsDeletion }
	}
}
