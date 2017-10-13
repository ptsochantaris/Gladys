import Foundation
import FileProvider

let modelAccessQueue = DispatchQueue(label: "build.bru.Gladys.fileprovider.model.queue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

private class ModelFilePresenter: NSObject, NSFilePresenter {

	weak var model: Model?

	var presentedItemURL: URL? {
		return Model.fileUrl
	}

	var presentedItemOperationQueue: OperationQueue {
		return OperationQueue.main
	}

	func presentedItemDidChange() {
		model?.reloadDataIfNeeded()
	}
}

private let fileExtensionPresenter = ModelFilePresenter()

extension Model {

	static var coordinator: NSFileCoordinator {
		let coordinator = NSFileCoordinator(filePresenter: nil)
		coordinator.purposeIdentifier = NSFileProviderManager.default.providerIdentifier
		return coordinator
	}

	func prepareToSave() {}
	func saveDone() {}
	func saveComplete() {}

	func startupComplete() {
		fileExtensionPresenter.model = self
		NSFileCoordinator.addFilePresenter(fileExtensionPresenter)
	}

	func reloadCompleted() {
		NSFileProviderManager.default.signalEnumerator(for: .rootContainer) { error in
			if let e = error {
				log("Error signalling: \(e.localizedDescription)")
			}
		}
	}
}
