import Foundation

extension Model {
    nonisolated static var coordinator: NSFileCoordinator {
        NSFileCoordinator(filePresenter: nil)
    }

    static func prepareToSave() {}
    static func saveComplete() {}
    static func saveIndexComplete() {}
    static func startupComplete() {}
}
