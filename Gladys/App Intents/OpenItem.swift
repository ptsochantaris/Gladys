import AppIntents
import Foundation
import GladysCommon

extension GladysAppIntents {
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    @AppIntent(schema: .system.open)
    struct OpenItem: OpenIntent {
        @Parameter(title: "Item")
        var target: ArchivedItemEntity

        static var title: LocalizedStringResource {
            "Open item"
        }

        static let supportedModes: IntentModes = .foreground

        func perform() async throws -> some IntentResult {
            HighlightRequest.send(uuid: target.id.uuidString, extraAction: .none)
            return .result()
        }
    }
}
