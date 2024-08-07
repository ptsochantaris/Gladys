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

extension UISceneSession {
    var associatedFilter: Filter {
        if let existing = userInfo?[kGladysMainFilter] as? Filter {
            return existing
        }
        let newFilter = Filter()
        if userInfo == nil {
            userInfo = [kGladysMainFilter: newFilter]
        } else {
            userInfo![kGladysMainFilter] = newFilter
        }
        return newFilter
    }
}

extension UIView {
    var associatedFilter: Filter? {
        let w = (self as? UIWindow) ?? window
        return w?.windowScene?.session.associatedFilter
    }
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
                    WidgetCenter.shared.reloadAllTimelines()
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

    @available(iOS 16, *)
    static func createItem(provider: DataImporter, title: String?, note: String?, labels: [GladysAppIntents.ArchivedItemLabel]) async throws -> some IntentResult & ReturnsValue<GladysAppIntents.ArchivedItemEntity> & OpensIntent {
        let importOverrides = ImportOverrides(title: title, note: note, labels: labels.map(\.id))
        let result = pasteItems(from: [provider], overrides: importOverrides)
        return try await GladysAppIntents.processCreationResult(result)
    }

    @discardableResult
    static func pasteItems(from providers: [DataImporter], overrides: ImportOverrides?) -> PasteResult {
        if providers.isEmpty {
            return .noData
        }

        let currentFilter = currentWindow?.associatedFilter

        var items = [ArchivedItem]()
        var addedStuff = false
        for provider in providers { // separate item for each provider in the pasteboard
            for item in ArchivedItem.importData(providers: [provider], overrides: overrides) {
                if let currentFilter, currentFilter.isFilteringLabels, !PersistedOptions.dontAutoLabelNewItems {
                    item.labels = currentFilter.enabledLabelsForItems
                }
                DropStore.insert(drop: item, at: 0)
                items.append(item)
                addedStuff = true
            }
        }

        if addedStuff {
            currentFilter?.update(signalUpdate: .animated)
        }

        return .success(items)
    }
}
