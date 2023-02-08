import Foundation
#if os(iOS)
    import UIKit
#endif

public final class FileMonitor: NSObject, NSFilePresenter {
    public var presentedItemURL: URL?

    public var presentedItemOperationQueue = OperationQueue.main

    public func presentedSubitemDidChange(at url: URL) {
        completion(url)
    }

    private let completion: (URL) -> Void

    private var notificationObservers = [Task<Void, Never>]()

    public init(directory: URL, completion: @escaping (URL) -> Void) {
        log("Starting monitoring of \(directory.path)")
        presentedItemURL = directory
        self.completion = completion

        super.init()

        NSFileCoordinator.addFilePresenter(self)

        #if os(iOS)
            let task1 = Task {
                for await _ in await notifications(named: UIApplication.willEnterForegroundNotification) {
                    NSFileCoordinator.addFilePresenter(self)
                }
            }
            let task2 = Task {
                for await _ in await notifications(named: UIApplication.didEnterBackgroundNotification) {
                    NSFileCoordinator.removeFilePresenter(self)
                }
            }
            notificationObservers = [task1, task2]
        #endif
    }

    public func stop() {
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
