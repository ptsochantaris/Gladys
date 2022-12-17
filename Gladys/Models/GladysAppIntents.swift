#if canImport(AppIntents)

    import AppIntents
    import Foundation
    import UniformTypeIdentifiers

    @available(iOS 16, *)
    enum GladysAppIntents {
        struct ArchivedItemEntity: AppEntity, Identifiable {
            struct ArchivedItemQuery: EntityStringQuery {
                @MainActor
                func entities(matching string: String) async throws -> [ArchivedItemEntity] {
                    let filter = Filter()
                    filter.text = string
                    return filter.filteredDrops.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
                }

                @MainActor
                func entities(for identifiers: [ID]) async throws -> [ArchivedItemEntity] {
                    identifiers.compactMap { Model.item(uuid: $0) }.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
                }

                @MainActor
                func suggestedEntities() async throws -> [ArchivedItemEntity] {
                    Model.allDrops.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
                }
            }

            let id: UUID
            let title: String

            static var defaultQuery = ArchivedItemQuery()

            static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Item" }

            var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: title) }
        }

        struct ArchivedItemLabel: AppEntity, Identifiable {
            struct ArchivedItemLabelQuery: EntityStringQuery {
                func entities(matching string: String) async throws -> [ArchivedItemLabel] {
                    let all = try await suggestedEntities()
                    return all.filter { $0.id.localizedCaseInsensitiveContains(string) }
                }

                @MainActor
                func entities(for identifiers: [ID]) async throws -> [ArchivedItemLabel] {
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

                @MainActor
                func suggestedEntities() async throws -> [ArchivedItemLabel] {
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

            let id: String

            static var defaultQuery = ArchivedItemLabelQuery()

            static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Label" }

            var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: id) }
        }
        
        struct DeleteItem: AppIntent {
            @Parameter(title: "Item")
            var entity: ArchivedItemEntity?
            
            static var title: LocalizedStringResource { "Delete item" }
            
            @MainActor
            func perform() async throws -> some IntentResult {
                guard let entity,
                      let item = Model.item(uuid: entity.id.uuidString)
                else {
                    throw Error.itemNotFound
                }
                Model.delete(items: [item])
                return .result()
            }
        }

        struct CopyItem: AppIntent {
            @Parameter(title: "Item")
            var entity: ArchivedItemEntity?
            
            static var title: LocalizedStringResource { "Copy item to clipboard" }
            
            @MainActor
            func perform() async throws -> some IntentResult {
                guard let entity,
                      let item = Model.item(uuid: entity.id.uuidString)
                else {
                    throw Error.itemNotFound
                }
                item.copyToPasteboard(donateShortcut: false)
                return .result()
            }
        }

        struct OpenGladys: AppIntent {
            @Parameter(title: "Item")
            var entity: ArchivedItemEntity?

            enum OpenGladysAction: String, AppEnum {
                case highlight, details, tryQuicklook, tryOpen
                static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Action" }
                static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
                    .highlight: DisplayRepresentation(stringLiteral: "Highlight"),
                    .details: DisplayRepresentation(stringLiteral: "Info"),
                    .tryQuicklook: DisplayRepresentation(stringLiteral: "Quicklook"),
                    .tryOpen: DisplayRepresentation(stringLiteral: "Open")
                ]
            }

            struct ActionProvider: DynamicOptionsProvider {
                func results() async throws -> [OpenGladysAction] {
                    [.highlight, .details, .tryOpen, .tryQuicklook]
                }
            }

            @Parameter(title: "Action", optionsProvider: ActionProvider())
            var action: OpenGladysAction

            static var title: LocalizedStringResource { "Select item" }

            static var openAppWhenRun = true

            @MainActor
            func perform() async throws -> some IntentResult {
                guard let entity else {
                    throw Error.itemNotFound
                }

                let itemUUID = entity.id.uuidString

                let request: HighlightRequest
                switch action {
                case .highlight:
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

            @Parameter(title: "Custom Name")
            var customName: String?

            @Parameter(title: "Note")
            var note: String?

            @Parameter(title: "Labels")
            var labels: [ArchivedItemLabel]?

            static var title: LocalizedStringResource { "Create item from file" }

            @MainActor
            func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
                let data: IntentFile
                if let file {
                    data = file
                } else {
                    data = try await $file.requestValue()
                }

                let p = NSItemProvider(item: data.data as NSData, typeIdentifier: (data.type ?? .data).identifier)
                p.suggestedName = data.filename
                return try await GladysAppIntents.createItem(provider: p, title: customName, note: note, labels: labels ?? [])
            }
        }

        struct CreateItemFromUrl: AppIntent {
            @Parameter(title: "URL")
            var url: URL?

            @Parameter(title: "Custom Name")
            var customName: String?

            @Parameter(title: "Note")
            var note: String?

            @Parameter(title: "Labels")
            var labels: [ArchivedItemLabel]?

            static var title: LocalizedStringResource { "Create item from link" }

            @MainActor
            func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
                let data: URL
                if let url {
                    data = url
                } else {
                    data = try await $url.requestValue()
                }

                let p = NSItemProvider(object: data as NSURL)
                return try await GladysAppIntents.createItem(provider: p, title: customName, note: note, labels: labels ?? [])
            }
        }

        struct CreateItemFromText: AppIntent {
            @Parameter(title: "Text")
            var text: String?

            @Parameter(title: "Custom Name")
            var customName: String?

            @Parameter(title: "Note")
            var note: String?
            
            @Parameter(title: "Labels")
            var labels: [ArchivedItemLabel]?

            static var title: LocalizedStringResource { "Create item from text" }

            @MainActor
            func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
                let data: String
                if let text {
                    data = text
                } else {
                    data = try await $text.requestValue()
                }

                let p = NSItemProvider(object: data as NSString)
                return try await GladysAppIntents.createItem(provider: p, title: customName, note: note, labels: labels ?? [])
            }
        }

        private static func createItem(provider: NSItemProvider, title: String?, note: String?, labels: [ArchivedItemLabel]) async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let importOverrides = ImportOverrides(title: title, note: note, labels: labels.map { $0.id })
            switch await Model.pasteItems(from: [provider], overrides: importOverrides) {
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
                for _ in 0 ..< 10 {
                    let done = await Model.doneIngesting
                    if done { break }
                    try? await Task.sleep(nanoseconds: 500 * NSEC_PER_MSEC)
                }
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
                AppShortcut(intent: CopyItem(),
                            phrases: ["Copy \(.applicationName) item to clipboard"],
                            shortTitle: "Copy to clipboard",
                            systemImageName: "doc.on.doc")
                
                AppShortcut(intent: OpenGladys(),
                            phrases: ["Select \(.applicationName) item"],
                            shortTitle: "Select item",
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
                
                AppShortcut(intent: DeleteItem(),
                            phrases: ["Delete \(.applicationName) item"],
                            shortTitle: "Delete item",
                            systemImageName: "xmark.bin")

            }
        }
    }

#endif
