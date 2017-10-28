import Foundation
import FileProvider

let modelAccessQueue = DispatchQueue(label: "build.bru.Gladys.fileprovider.model.queue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

private class ModelFilePresenter: NSObject, NSFilePresenter {

	var presentedItemURL: URL? {
		return Model.fileUrl
	}

	var presentedItemOperationQueue: OperationQueue {
		return OperationQueue.main
	}

	func presentedItemDidChange() {
		Model.reloadDataIfNeeded()
	}
}

private let fileExtensionPresenter = ModelFilePresenter()

extension Model {

	static var coordinator: NSFileCoordinator {
		let coordinator = NSFileCoordinator(filePresenter: nil)
		coordinator.purposeIdentifier = NSFileProviderManager.default.providerIdentifier
		return coordinator
	}

	static func prepareToSave() {}
	static func saveDone() {}
	static func saveComplete() {}

	static func startupComplete() {
		NSFileCoordinator.addFilePresenter(fileExtensionPresenter)
	}

	static func signalRootChange() {
		NSFileProviderManager.default.signalEnumerator(for: .rootContainer) { error in
			if let e = error {
				log("Error signalling: \(e.localizedDescription)")
			}
		}
	}

	static func signalWorkingSetChange() {
		NSFileProviderManager.default.signalEnumerator(for: .workingSet) { error in
			if let e = error {
				log("Error signalling: \(e.localizedDescription)")
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
