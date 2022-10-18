//
//  GladysAppIntents.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 13/09/2022.
//  Copyright © 2022 Paul Tsochantaris. All rights reserved.
//

import Foundation
import AppIntents
import UniformTypeIdentifiers

@available(iOS 16, *)
enum GladysAppIntents {
    
    struct ArchivedItemEntity: AppEntity, Identifiable {
        struct Query: EntityStringQuery {
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

        let id: UUID
        let title: String
        
        static var defaultQuery = Query()

        static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Item" }
        
        var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: title) }
    }
    
    struct OpenGladys: AppIntent {
        @Parameter(title: "Item")
        var entity: ArchivedItemEntity?

        @Parameter(title: "Action", optionsProvider: Action.Provider())
        var action: Action?

        enum Action: String, AppEnum {
            case highlight, details, tryQuicklook, tryOpen
            static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Action" }
            static var caseDisplayRepresentations: [Action: DisplayRepresentation] = [
                .highlight: "Highlight",
                .details: "Info",
                .tryOpen: "Open",
                .tryQuicklook: "Quicklook"
            ]
            
            struct Provider: DynamicOptionsProvider {
                func results() async throws -> [Action] {
                    [.highlight, .details, .tryOpen, .tryQuicklook]
                }
            }
        }
        
        static var title: LocalizedStringResource { "Open" }
        
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

    struct CreateItemFromFile: AppIntent {
        @Parameter(title: "File")
        var file: IntentFile?

        static var title: LocalizedStringResource { "Create item from file" }
                
        @MainActor
        func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let data: IntentFile
            if let file = file {
                data = file
            } else {
                data = try await $file.requestValue()
            }
            
            let p = NSItemProvider(item: data.data as NSData,
                                   typeIdentifier: (data.type ?? .data).identifier)
            p.suggestedName = data.filename
            return try await GladysAppIntents.createItems(providers: [p])
        }
    }

    struct CreateItemFromUrl: AppIntent {
        @Parameter(title: "URL")
        var url: URL?
        
        static var title: LocalizedStringResource { "Create item from link" }
        
        @MainActor
        func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let data: URL
            if let url = url {
                data = url
            } else {
                data = try await $url.requestValue()
            }
            
            let p = NSItemProvider(item: data as NSURL, typeIdentifier: UTType.url.identifier)
            return try await GladysAppIntents.createItems(providers: [p])
        }
    }
    
    struct CreateItemFromText: AppIntent {
        @Parameter(title: "URL")
        var text: String?
        
        static var title: LocalizedStringResource { "Create item from text" }
        
        @MainActor
        func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let data: String
            if let text = text {
                data = text
            } else {
                data = try await $text.requestValue()
            }
            
            let p = NSItemProvider(item: data as NSString, typeIdentifier: UTType.utf8PlainText.identifier)
            return try await GladysAppIntents.createItems(providers: [p])
        }
    }
    
    private static func createItems(providers: [NSItemProvider]) async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
        switch await Model.pasteItems(from: providers, overrides: nil) {
        case .noData:
            throw Error.noItemsCreated
        case let .success(items):
            guard let item = items.first else {
                throw Error.noItemsCreated
            }
            let entity = ArchivedItemEntity(id: item.uuid, title: item.displayTitleOrUuid)
            let hi = OpenGladys()
            hi.entity = entity
            hi.action = .highlight
            return .result(value: entity, opensIntent: hi)
        }
    }
    
    enum Error: Swift.Error, CustomLocalizedStringResourceConvertible {
        case noItemsCreated
        case itemNotFound
        
        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .noItemsCreated: return "No items were created from this data"
            case .itemNotFound: return "Item could not be found"
            }
        }
    }

    struct GladysShortcuts: AppShortcutsProvider {
        static var appShortcuts: [AppShortcut] {
            AppShortcut(intent: OpenGladys(),
                        phrases: ["Open \(.applicationName)"],
                        shortTitle: "Open",
                        systemImageName: "square.grid.3x3.topleft.filled")

            AppShortcut(intent: CreateItemFromText(),
                        phrases: ["Create \(.applicationName) item from text"],
                        shortTitle: "Create from text",
                        systemImageName: "doc.text")

            AppShortcut(intent: CreateItemFromText(),
                        phrases: ["Create \(.applicationName) item from link"],
                        shortTitle: "Create from link",
                        systemImageName: "link")

            AppShortcut(intent: CreateItemFromFile(),
                        phrases: ["Create \(.applicationName) item from file"],
                        shortTitle: "Create from file",
                        systemImageName: "doc")
        }
    }
}
