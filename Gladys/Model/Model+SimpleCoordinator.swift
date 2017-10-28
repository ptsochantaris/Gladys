import Foundation

extension Model {
	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: nil)
	}

	static func prepareToSave() {}
	static func saveDone() {}
	static func saveComplete() {}
	static func startupComplete() {}
	static func reloadCompleted() {}
}
