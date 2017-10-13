import Foundation

extension Model {
	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: nil)
	}

	func prepareToSave() {}
	func saveDone() {}
	func saveComplete() {}
	func startupComplete() {}
	func reloadCompleted() {}
}
