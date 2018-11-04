
import FileProvider

extension Model {

	static var coordinator: NSFileCoordinator {
		let coordinator = NSFileCoordinator(filePresenter: nil)
		coordinator.purposeIdentifier = NSFileProviderManager.default.providerIdentifier
		return coordinator
	}

	static func prepareToSave() {}
	static func saveComplete() {}
	static func saveIndexComplete() {}
	static func startupComplete() {}
	static func reloadCompleted() {}
}
