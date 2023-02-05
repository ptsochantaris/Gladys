import Foundation
import GladysCommon

final class ModelFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL? = itemsDirectoryUrl

    let presentedItemOperationQueue = OperationQueue()

    func presentedItemDidChange() {
        Task { @MainActor in
            if DropStore.doneIngesting {
                Model.reloadDataIfNeeded()
            }
        }
    }
}
