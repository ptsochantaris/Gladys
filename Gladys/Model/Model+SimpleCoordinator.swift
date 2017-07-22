import Foundation

extension Model {
	static var coordinator: NSFileCoordinator {
		let coordinator = NSFileCoordinator(filePresenter: nil)
		coordinator.purposeIdentifier = Bundle.main.bundleIdentifier!
		return coordinator
	}

	func prepareToSave() {}
	func saveDone() {}
	func saveComplete() {}
}
