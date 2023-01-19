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

    public init(directory: URL, completion: @escaping (URL) -> Void) {
        log("Starting monitoring of \(directory.path)")
        presentedItemURL = directory
        self.completion = completion

        super.init()

        NSFileCoordinator.addFilePresenter(self)

        #if os(iOS)
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(foregrounded), name: UIApplication.willEnterForegroundNotification, object: nil)
            nc.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
        #endif
    }

    #if os(iOS)
        @objc private func foregrounded() {
            NSFileCoordinator.addFilePresenter(self)
        }

        @objc private func backgrounded() {
            NSFileCoordinator.removeFilePresenter(self)
        }
    #endif

    public func stop() {
        if let p = presentedItemURL {
            log("Ending monitoring of \(p.path)")
        }
        NotificationCenter.default.removeObserver(self)
        NSFileCoordinator.removeFilePresenter(self)
    }
}
