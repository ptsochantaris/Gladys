import Foundation

extension Model {
    static var coordinator: NSFileCoordinator {
        NSFileCoordinator(filePresenter: nil)
    }

    static func prepareToSave() {}
    static func saveComplete(wasIndexOnly _: Bool) {}
    static func startupComplete() {}
}
