import Foundation

extension Model {
	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: nil)
	}

	static func prepareToSave() {}
	static func saveComplete() {}
	static func saveIndexComplete() {}
	static func startupComplete() {}
}
