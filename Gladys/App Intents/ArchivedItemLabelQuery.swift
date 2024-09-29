import AppIntents
import Foundation
import GladysCommon
import GladysUI

extension GladysAppIntents {
    struct ArchivedItemLabelQuery: EntityStringQuery {
        func entities(matching string: String) async throws -> [ArchivedItemLabel] {
            let all = try await suggestedEntities()
            return all.filter { $0.id.localizedCaseInsensitiveContains(string) }
        }

        func entities(for identifiers: [ArchivedItemLabel.ID]) async throws -> [ArchivedItemLabel] {
            await MainActor.run {
                let filter = Filter()
                filter.rebuildLabels()
                let names = Set(filter.labelToggles.map(\.function.displayText))
                return identifiers.compactMap { entityId in
                    if names.contains(entityId) {
                        return ArchivedItemLabel(id: entityId)
                    }
                    return nil
                }
            }
        }

        func suggestedEntities() async throws -> [ArchivedItemLabel] {
            await MainActor.run {
                let filter = Filter()
                filter.rebuildLabels()
                return filter.labelToggles.compactMap {
                    if case .userLabel = $0.function {
                        return ArchivedItemLabel(id: $0.function.displayText)
                    }
                    return nil
                }
            }
        }
    }
}
