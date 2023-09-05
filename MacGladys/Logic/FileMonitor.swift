import Foundation
import GladysCommon

final class FileMonitor: NSObject, NSFilePresenter {
    var presentedItemURL: URL?

    var presentedItemOperationQueue = OperationQueue.main

    func presentedSubitemDidChange(at url: URL) {
        completion(url)
    }

    private let completion: (URL) -> Void

    private var notificationObservers = [Task<Void, Never>]()

    init(directory: URL, completion: @escaping (URL) -> Void) {
        log("Starting monitoring of \(directory.path)")
        presentedItemURL = directory
        self.completion = completion

        super.init()

        NSFileCoordinator.addFilePresenter(self)

        #if canImport(UIKit)
            let task1 = Task { @MainActor in
                for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
                    NSFileCoordinator.addFilePresenter(self)
                }
            }
            let task2 = Task { @MainActor in
                for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                    NSFileCoordinator.removeFilePresenter(self)
                }
            }
            notificationObservers = [task1, task2]
        #endif
    }

    func stop() {
        if let p = presentedItemURL {
            log("Ending monitoring of \(p.path)")
        }
        for task in notificationObservers {
            task.cancel()
        }
        notificationObservers.removeAll()
        NSFileCoordinator.removeFilePresenter(self)
    }
}
