import AppIntents
import Foundation
import GladysCommon
import GladysUI

extension GladysAppIntents {
    struct OpenGladys: AppIntent {
        @Parameter(title: "Item")
        var entity: ArchivedItemEntity?

        enum OpenGladysAction: String, AppEnum {
            case highlight, details, tryQuicklook, tryOpen, userDefault
            static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Action" }
            static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
                .highlight: DisplayRepresentation(stringLiteral: "Highlight"),
                .details: DisplayRepresentation(stringLiteral: "Info"),
                .tryQuicklook: DisplayRepresentation(stringLiteral: "Quicklook"),
                .tryOpen: DisplayRepresentation(stringLiteral: "Open"),
                .userDefault: DisplayRepresentation(stringLiteral: "Default Action")
            ]
        }

        struct ActionProvider: DynamicOptionsProvider {
            func results() async throws -> [OpenGladysAction] {
                [.highlight, .details, .tryOpen, .tryQuicklook, .userDefault]
            }
        }

        @Parameter(title: "Action", optionsProvider: ActionProvider())
        var action: OpenGladysAction

        static var title: LocalizedStringResource { "Select item" }

        static let openAppWhenRun = true

        func perform() async throws -> some IntentResult {
            guard let entity else {
                throw GladysAppIntentsError.itemNotFound
            }

            let extraAction: HighlightRequest.Action =
                switch action {
                case .highlight: .none
                case .tryQuicklook: .preview(nil)
                case .tryOpen: .open
                case .details: .detail
                case .userDefault: .userDefault
                }

            HighlightRequest.send(uuid: entity.id.uuidString, extraAction: extraAction)

            return .result()
        }
    }
}
