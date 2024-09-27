import AppIntents
import Foundation
import GladysCommon
import GladysUI
import SwiftUI
import WidgetKit

struct LabelQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [LabelOption] {
        let all = try await suggestedEntities()
        return all.filter { $0.id.localizedCaseInsensitiveContains(string) }
    }

    func entities(for identifiers: [String]) async throws -> [LabelOption] {
        await Task { @MainActor in
            let filter = Filter(manualDropSource: ContiguousArray(LiteModel.allItems()))
            filter.rebuildLabels()
            let names = Set(filter.labelToggles.map(\.function.displayText))
            return identifiers.compactMap { entityId in
                if entityId == "" {
                    return LabelOption.clear
                }
                if names.contains(entityId) {
                    return LabelOption(id: entityId, label: entityId)
                }
                return nil
            }
        }.value
    }

    func suggestedEntities() async throws -> [LabelOption] {
        await Task { @MainActor in
            let filter = Filter(manualDropSource: ContiguousArray(LiteModel.allItems()))
            filter.rebuildLabels()
            return [LabelOption.clear] + filter.labelToggles.compactMap {
                if case .userLabel = $0.function {
                    let labelText = $0.function.displayText
                    return LabelOption(id: labelText, label: labelText)
                }
                return nil
            }
        }.value
    }
}
