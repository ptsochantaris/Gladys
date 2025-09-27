import Foundation

#if canImport(AppKit)
    public enum Coordination {
        static var coordinator: NSFileCoordinator {
            NSFileCoordinator(filePresenter: nil)
        }
    }

#elseif canImport(UIKit)

    import GladysCommon
    import UIKit

    public enum Coordination {
        private final class ModelFilePresenter: NSObject, NSFilePresenter, Sendable {
            let presentedItemURL: URL? = itemsDirectoryUrl

            let presentedItemOperationQueue = OperationQueue()

            func presentedItemDidChange() {
                Task {
                    try! await Model.reloadIfPossible()
                }
            }
        }

        static var coordinator: NSFileCoordinator {
            NSFileCoordinator(filePresenter: filePresenter)
        }

        private static let filePresenter = ModelFilePresenter()

        public static func beginMonitoringChanges() {
            notifications(for: UIApplication.willEnterForegroundNotification) { _ in
                NSFileCoordinator.addFilePresenter(filePresenter)
                try! await Model.reloadIfPossible()
            }

            notifications(for: UIApplication.didEnterBackgroundNotification) { _ in
                NSFileCoordinator.removeFilePresenter(filePresenter)
            }

            NSFileCoordinator.addFilePresenter(filePresenter)
        }
    }
#endif
