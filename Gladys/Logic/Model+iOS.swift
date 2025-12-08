import AppIntents
import Foundation
import GladysCommon
import GladysUI
import GladysUIKit
import Maintini
import UIKit
import WatchConnectivity

#if canImport(WidgetKit)
    import WidgetKit
#endif

@MainActor
var currentWindow: UIWindow? {
    UIApplication.shared.connectedScenes.filter { $0.activationState != .background }.compactMap { ($0 as? UIWindowScene)?.windows.first }.lazy.first
}

extension Model {
    private static var watchDelegate: WatchDelegate?

    static func registerStateHandler() {
        stateHandler = { state in
            switch state {
            case .migrated:
                break

            case let .saveComplete(dueToSyncFetch):
                #if canImport(WidgetKit)
                    #if os(visionOS)
                        if #available(visionOS 26.0, *) {
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    #else
                        WidgetCenter.shared.reloadAllTimelines()
                    #endif
                #endif

                watchDelegate?.updateContext()

                Task {
                    do {
                        if try await shouldSync(dueToSyncFetch: dueToSyncFetch) {
                            try await CloudManager.syncAfterSaveIfNeeded()
                        }
                    } catch {
                        log("Error in sync after save: \(error.localizedDescription)")
                    }
                }

                Maintini.endMaintaining()

            case .willSave:
                Maintini.startMaintaining()

            case .startupComplete:
                if WCSession.isSupported() {
                    watchDelegate = WatchDelegate()
                }
            }
        }
    }

    static func createItem(provider: DataImporter, title: String?, note: String?, labels: [GladysAppIntents.ArchivedItemLabel], currentFilter: Filter?) async throws -> some IntentResult & ReturnsValue<GladysAppIntents.ArchivedItemEntity> & OpensIntent {
        let importOverrides = ImportOverrides(title: title, note: note, labels: labels.map(\.id))
        let result = pasteItems(from: [provider], overrides: importOverrides, currentFilter: currentFilter)
        return try await GladysAppIntents.processCreationResult(result)
    }
}
