import AppIntents
import Foundation
import GladysCommon
import GladysUI

extension GladysAppIntents {
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    @AppIntent(schema: .system.searchInApp)
    struct SearchInGladys: ShowInAppSearchResultsIntent {
        static let searchScopes: [StringSearchScope] = [.general]

        var criteria: StringSearchCriteria

        static var title: LocalizedStringResource {
            "Search in Gladys"
        }

        static let supportedModes: IntentModes = .foreground

        func perform() async throws -> some IntentResult {
            let term = criteria.term
            await MainActor.run {
                Model.startSearch(text: term)
            }
            return .result()
        }
    }
}
