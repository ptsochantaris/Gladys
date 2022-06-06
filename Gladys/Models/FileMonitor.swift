//
//  FileMonitor.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 30/10/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

#if os(iOS)
    import UIKit
#else
    import Foundation
#endif

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

    func stop() {
        if let p = presentedItemURL {
            log("Ending monitoring of \(p.path)")
        }
        NotificationCenter.default.removeObserver(self)
        NSFileCoordinator.removeFilePresenter(self)
    }
}
