import Foundation

#if canImport(AppKit)
    public enum Coordination {
        nonisolated static var coordinator: NSFileCoordinator {
            NSFileCoordinator(filePresenter: nil)
        }
    }

#elseif canImport(UIKit)

    import GladysCommon
    import Minions
    import UIKit

    public enum Coordination {
        private final class ModelFilePresenter: NSObject, NSFilePresenter {
            let presentedItemURL: URL? = itemsDirectoryUrl

            let presentedItemOperationQueue = OperationQueue()

            func presentedItemDidChange() {
                Task {
                    if await DropStore.doneIngesting {
                        try! await Model.reloadDataIfNeeded()
                    }
                }
            }
        }

        nonisolated static var coordinator: NSFileCoordinator {
            NSFileCoordinator(filePresenter: filePresenter)
        }

        private static let filePresenter = ModelFilePresenter()

        @MainActor
        public static func beginMonitoringChanges() {
            #notifications(for: UIApplication.willEnterForegroundNotification) { _ in
                NSFileCoordinator.addFilePresenter(filePresenter)
                if DropStore.doneIngesting {
                    try! await Model.reloadDataIfNeeded()
                }
                return true
            }

            #notifications(for: UIApplication.didEnterBackgroundNotification) { _ in
                NSFileCoordinator.removeFilePresenter(filePresenter)
                return true
            }

            NSFileCoordinator.addFilePresenter(filePresenter)
        }
    }
#endif
