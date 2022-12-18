import Foundation

extension Model {
    static var coordinator: NSFileCoordinator {
        NSFileCoordinator(filePresenter: nil)
    }

    static func prepareToSave() {}
    static func saveComplete() {}
    static func saveIndexComplete() {}
    static func startupComplete() {}
}
