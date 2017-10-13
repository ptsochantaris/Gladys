import Foundation
import FileProvider

let modelAccessQueue = DispatchQueue(label: "build.bru.Gladys.fileprovider.model.queue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

extension Model {
	static var coordinator: NSFileCoordinator {
		let coordinator = NSFileCoordinator(filePresenter: nil)
		coordinator.purposeIdentifier = NSFileProviderManager.default.providerIdentifier
		return coordinator
	}

	func prepareToSave() {}
	func saveDone() {}
	func saveComplete() {}
	func startupComplete() {}
}
