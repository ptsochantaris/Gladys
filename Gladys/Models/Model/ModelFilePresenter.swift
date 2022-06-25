import Foundation

final class ModelFilePresenter: NSObject, NSFilePresenter {
    var presentedItemURL: URL? {
        Model.itemsDirectoryUrl
    }

    private let _presentedItemOperationQueue = OperationQueue()
    var presentedItemOperationQueue: OperationQueue {
        _presentedItemOperationQueue // requests will be dispatched to main below
    }

    func presentedItemDidChange() {
        DispatchQueue.main.async {
            if Model.doneIngesting {
                Model.reloadDataIfNeeded()
            }
        }
    }
}
