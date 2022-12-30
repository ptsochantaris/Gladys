import Foundation

final class ModelFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL? = Model.itemsDirectoryUrl

    let presentedItemOperationQueue = OperationQueue()

    func presentedItemDidChange() {
        Task { @MainActor in
            if Model.doneIngesting {
                Model.reloadDataIfNeeded()
            }
        }
    }
}
