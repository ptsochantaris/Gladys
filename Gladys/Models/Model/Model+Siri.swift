import Foundation
import Intents
import UIKit
#if canImport(AppIntents)
import AppIntents
import UniformTypeIdentifiers
#endif

extension Model {
    static var pasteIntent: PasteClipboardIntent {
        let intent = PasteClipboardIntent()
        intent.suggestedInvocationPhrase = "Paste in Gladys"
        return intent
    }
    
    static func clearLegacyIntents() {
        if #available(iOS 16, *) {
            INInteraction.deleteAll() // using app intents now
        }
    }
    
    static func donatePasteIntent() {
        if #available(iOS 16, *) {
            log("Will not donate SiriKit paste shortcut")
        } else {
            let interaction = INInteraction(intent: pasteIntent, response: nil)
            interaction.identifier = "paste-in-gladys"
            interaction.donate { error in
                if let error = error {
                    log("Error donating paste shortcut: \(error.localizedDescription)")
                } else {
                    log("Donated paste shortcut")
                }
            }
        }
    }
}

enum GladysAppIntents {
    @available(iOS 16.0, *)
    struct ArchivedItemQuery: EntityStringQuery {
        @MainActor
        func entities(matching string: String) async throws -> [ArchivedItemEntity] {
            let filter = Filter()
            filter.text = string
            return filter.filteredDrops.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
        }
        
        @MainActor
        func entities(for identifiers: [ArchivedItemEntity.ID]) async throws -> [ArchivedItemEntity] {
            return identifiers.compactMap { Model.item(uuid: $0 ) }.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
        }
        
        @MainActor
        func suggestedEntities() async throws -> [ArchivedItemEntity] {
            return Model.drops.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
        }
    }

    @available(iOS 16.0, *)
    struct ArchivedItemEntity: AppEntity, Identifiable {
        let id: UUID
        let title: String
        
        static var defaultQuery = ArchivedItemQuery()

        static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Item" }
        
        var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: title) }
    }
    
    @available(iOS 16.0, *)
    struct HighlightItem: AppIntent {
        @Parameter(title: "Item")
        var entity: ArchivedItemEntity?

        @Parameter(title: "Action", optionsProvider: ArchivedItemHighlightAction.OptionsProvider())
        var action: ArchivedItemHighlightAction?

        enum ArchivedItemHighlightAction: String, AppEnum {
            case highlight, details, tryQuicklook, tryOpen
            static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Action" }
            static var caseDisplayRepresentations: [ArchivedItemHighlightAction: DisplayRepresentation] = [
                .highlight: "Highlight",
                .details: "Info",
                .tryOpen: "Open",
                .tryQuicklook: "Quicklook"
            ]
            
            struct OptionsProvider: DynamicOptionsProvider {
                func results() async throws -> [ArchivedItemHighlightAction] {
                    [.highlight, .details, .tryOpen, .tryQuicklook]
                }
            }
        }
        
        static var title: LocalizedStringResource { "Open Gladys" }
        
        enum Error: Swift.Error, CustomLocalizedStringResourceConvertible {
            case itemNotFound
            
            var localizedStringResource: LocalizedStringResource {
                switch self {
                case .itemNotFound: return "Item could not be found"
                }
            }
        }

        static var openAppWhenRun = true
        
        @MainActor
        func perform() async throws -> some IntentResult {
            guard let entity else {
                throw Error.itemNotFound
            }
            
            let itemUUID = entity.id.uuidString
                            
            let request: HighlightRequest
            switch action {
            case .highlight, .none:
                request = HighlightRequest(uuid: itemUUID, extraAction: .none)
            case .tryQuicklook:
                request = HighlightRequest(uuid: itemUUID, extraAction: .preview(nil))
            case .tryOpen:
                request = HighlightRequest(uuid: itemUUID, extraAction: .open)
            case .details:
                request = HighlightRequest(uuid: itemUUID, extraAction: .detail)
            }
            sendNotification(name: .HighlightItemRequested, object: request)
            return .result()
        }
    }
    
    @available(iOS 16.0, *)
    struct AddNewItem: AppIntent {
        @Parameter(title: "Source File")
        var file: IntentFile?

        static var title: LocalizedStringResource { "Keep File in Gladys" }
        
        enum Error: Swift.Error, CustomLocalizedStringResourceConvertible {
            case noItemsCreated
            
            var localizedStringResource: LocalizedStringResource {
                switch self {
                case .noItemsCreated: return "No items were created from the provided data"
                }
            }
        }
        
        @MainActor
        func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let data: IntentFile
            if let file = file {
                data = file
            } else {
                data = try await $file.requestValue()
            }
            
            let typeIdentifier = (data.type ?? .data).identifier

            let p = NSItemProvider()
            p.suggestedName = data.filename
            p.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion -> Progress? in
                completion(data.data, nil)
                return nil
            }

            switch Model.pasteItems(from: [p], overrides: nil) {
            case .noData:
                throw Error.noItemsCreated
            case let .success(items):
                guard let item = items.first else {
                    throw Error.noItemsCreated
                }
                let entity = ArchivedItemEntity(id: item.uuid, title: item.displayTitleOrUuid)
                let hi = HighlightItem()
                hi.entity = entity
                hi.action = .highlight
                return .result(value: entity, opensIntent: hi)
            }
        }
    }
    
    @available(iOS 16.0, *)
    struct GladysShortcuts: AppShortcutsProvider {
        static var appShortcuts: [AppShortcut] {
            AppShortcut(intent: HighlightItem(),
                        phrases: ["Open \(.applicationName)"],
                        shortTitle: "Open",
                        systemImageName: "square.grid.3x3.topleft.filled")
            
            AppShortcut(intent: AddNewItem(),
                        phrases: ["Keep in \(.applicationName)"],
                        shortTitle: "Keep",
                        systemImageName: "arrow.down.doc")
        }
    }
}
