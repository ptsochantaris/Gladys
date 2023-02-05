import Foundation
#if canImport(Cocoa)
    import Cocoa
#endif
#if canImport(UIKit)
    import UIKit
#endif
import GladysCommon

extension Model {
    #if os(iOS)

        private final class ModelFilePresenter: NSObject, NSFilePresenter {
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

        public nonisolated static var coordinator: NSFileCoordinator {
            NSFileCoordinator(filePresenter: filePresenter)
        }

        private static var foregroundObserver: NSObjectProtocol?
        private static var backgroundObserver: NSObjectProtocol?

        public static func beginMonitoringChanges() {
            let n = NotificationCenter.default
            foregroundObserver = n.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                foregrounded()
            }
            backgroundObserver = n.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                backgrounded()
            }
            NSFileCoordinator.addFilePresenter(filePresenter)
        }

        private static let filePresenter = ModelFilePresenter()

        private static func foregrounded() {
            NSFileCoordinator.addFilePresenter(filePresenter)
            reloadDataIfNeeded()
        }

        private static func backgrounded() {
            NSFileCoordinator.removeFilePresenter(filePresenter)
        }

    #elseif os(macOS)
        public nonisolated static var coordinator: NSFileCoordinator {
            NSFileCoordinator(filePresenter: nil)
        }
    #endif
}
