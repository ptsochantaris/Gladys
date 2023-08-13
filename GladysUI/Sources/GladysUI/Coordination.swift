import Foundation
#if os(iOS) || os(visionOS)
    import GladysCommon
    import UIKit

    public enum Coordination {
        private final class ModelFilePresenter: NSObject, NSFilePresenter {
            let presentedItemURL: URL? = itemsDirectoryUrl

            let presentedItemOperationQueue = OperationQueue()

            func presentedItemDidChange() {
                Task { @MainActor in
                    if DropStore.doneIngesting {
                        await Model.reloadDataIfNeeded()
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
            Task {
                for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
                    NSFileCoordinator.addFilePresenter(filePresenter)
                    if DropStore.doneIngesting {
                        await Model.reloadDataIfNeeded()
                    }
                }
            }
            Task {
                for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                    NSFileCoordinator.removeFilePresenter(filePresenter)
                }
            }
            NSFileCoordinator.addFilePresenter(filePresenter)
        }
    }

#else
    enum Coordination {
        nonisolated static var coordinator: NSFileCoordinator {
            NSFileCoordinator(filePresenter: nil)
        }
    }
#endif
