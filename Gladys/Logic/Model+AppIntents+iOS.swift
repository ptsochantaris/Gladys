#if canImport(UIKit)
    import GladysCommon
    import GladysUI
    import UIKit

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
        @discardableResult
        static func pasteItems(from providers: [DataImporter], overrides: ImportOverrides?, currentFilter: Filter?) -> PasteResult {
            if providers.isEmpty {
                return .noData
            }

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
                sendNotification(name: .FiltersShouldUpdate)
            }

            return .success(items)
        }
    }
#endif
