import Foundation

extension Model {
	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: nil)
	}

	static func prepareToSave() {}
	static func saveComplete(wasIndexOnly: Bool) {}
	static func startupComplete() {}
}
