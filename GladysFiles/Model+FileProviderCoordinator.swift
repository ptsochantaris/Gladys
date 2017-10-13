import Foundation
import FileProvider

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
