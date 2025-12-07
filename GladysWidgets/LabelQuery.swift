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

    @MainActor
    func entities(for identifiers: [String]) async throws -> [LabelOption] {
        let allItems = await LiteModel.allItems()
        let filter = Filter(manualDropSource: allItems)
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
    }

    @MainActor
    func suggestedEntities() async throws -> [LabelOption] {
        let allItems = await LiteModel.allItems()
        let filter = Filter(manualDropSource: allItems)
        return [LabelOption.clear] + filter.labelToggles.compactMap {
            if case .userLabel = $0.function {
                let labelText = $0.function.displayText
                return LabelOption(id: labelText, label: labelText)
            }
            return nil
        }
    }
}
