#if os(macOS)
import Foundation
#else
import UIKit
#endif
import GladysCommon

final class FileMonitor: NSObject, NSFilePresenter {
    var presentedItemURL: URL?

    var presentedItemOperationQueue = OperationQueue.main

    func presentedSubitemDidChange(at url: URL) {
        completion(url)
    }

    private let completion: (URL) -> Void

    init(directory: URL, completion: @escaping (URL) -> Void) {
        log("Starting monitoring of \(directory.path)")
        presentedItemURL = directory
        self.completion = completion

        super.init()

        NSFileCoordinator.addFilePresenter(self)

        #if os(macOS)
        #else
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(foregrounded), name: UIApplication.willEnterForegroundNotification, object: nil)
            nc.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
        #endif
    }

    #if os(macOS)
    #else
        @objc private func foregrounded() {
            NSFileCoordinator.addFilePresenter(self)
        }

        @objc private func backgrounded() {
            NSFileCoordinator.removeFilePresenter(self)
        }
    #endif

    func stop() {
        if let p = presentedItemURL {
            log("Ending monitoring of \(p.path)")
        }
        NotificationCenter.default.removeObserver(self)
        NSFileCoordinator.removeFilePresenter(self)
    }
}
