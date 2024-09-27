#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif
import AppIntents
import GladysCommon
import GladysUI

@MainActor
protocol WidgetModel {
    associatedtype CreateReturnType: IntentResult & ReturnsValue<GladysAppIntents.ArchivedItemEntity> & OpensIntent

    static func createItem(provider _: DataImporter, title _: String?, note _: String?, labels _: [GladysAppIntents.ArchivedItemLabel]) async throws -> CreateReturnType

    #if canImport(AppKit)
        @discardableResult
        static func addItems(from _: NSPasteboard, at _: IndexPath, overrides _: ImportOverrides?, filterContext _: Filter?) -> PasteResult
    #else
        @discardableResult
        static func pasteItems(from _: [DataImporter], overrides _: ImportOverrides?) -> PasteResult
    #endif
}

enum GladysAppIntents {
    struct ArchivedItemEntity: AppEntity, Identifiable {
        struct ArchivedItemQuery: EntityStringQuery {
            func entities(matching string: String) async throws -> [ArchivedItemEntity] {
                await MainActor.run {
                    let filter = Filter()
                    filter.text = string
                    return filter.filteredDrops.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
                }
            }

            func entities(for identifiers: [ID]) async throws -> [ArchivedItemEntity] {
                await MainActor.run {
                    identifiers.compactMap { DropStore.item(uuid: $0) }.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
                }
            }

            func suggestedEntities() async throws -> [ArchivedItemEntity] {
                await MainActor.run {
                    DropStore.allDrops.map { ArchivedItemEntity(id: $0.uuid, title: $0.displayTitleOrUuid) }
                }
            }
        }

        let id: UUID
        let title: String

        static let defaultQuery = ArchivedItemQuery()

        static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Item" }

        var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: title) }
    }

    struct ArchivedItemLabel: AppEntity, Identifiable {
        struct ArchivedItemLabelQuery: EntityStringQuery {
            func entities(matching string: String) async throws -> [ArchivedItemLabel] {
                let all = try await suggestedEntities()
                return all.filter { $0.id.localizedCaseInsensitiveContains(string) }
            }

            func entities(for identifiers: [ID]) async throws -> [ArchivedItemLabel] {
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

        let id: String

        static let defaultQuery = ArchivedItemLabelQuery()

        static var typeDisplayRepresentation: TypeDisplayRepresentation { "Gladys Label" }

        var displayRepresentation: DisplayRepresentation { DisplayRepresentation(stringLiteral: id) }
    }

    struct DeleteItem: AppIntent {
        @Parameter(title: "Item")
        var entity: ArchivedItemEntity?

        static var title: LocalizedStringResource { "Delete item" }

        func perform() async throws -> some IntentResult {
            guard let entity,
                  let item = await DropStore.item(uuid: entity.id)
            else {
                throw Error.itemNotFound
            }
            await Model.delete(items: [item])
            return .result()
        }
    }

    struct CopyItem: AppIntent {
        @Parameter(title: "Item")
        var entity: ArchivedItemEntity?

        static var title: LocalizedStringResource { "Copy item to clipboard" }

        func perform() async throws -> some IntentResult {
            guard let entity,
                  let item = await DropStore.item(uuid: entity.id)
            else {
                throw Error.itemNotFound
            }
            await item.copyToPasteboard()
            return .result()
        }
    }

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
                throw Error.itemNotFound
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

    struct PasteIntoGladys: AppIntent {
        static var title: LocalizedStringResource { "Paste from clipboard" }

        static let openAppWhenRun = true

        func perform() async throws -> some IntentResult {
            let topIndex = IndexPath(item: 0, section: 0)
            #if canImport(UIKit)
                guard let p = UIPasteboard.general.itemProviders.first else {
                    throw Error.nothingInClipboard
                }
                let importer = DataImporter(itemProvider: p)
                await Model.pasteItems(from: [importer], overrides: nil)
            #else
                let pb = NSPasteboard.general
                guard let c = pb.pasteboardItems?.count, c > 0 else {
                    throw Error.nothingInClipboard
                }
                _ = await Model.addItems(from: pb, at: topIndex, overrides: .none, filterContext: nil)
            #endif
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

        func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let data: IntentFile = if let file {
                file
            } else {
                try await $file.requestValue()
            }

            let importer = DataImporter(type: (data.type ?? .data).identifier, data: data.data, suggestedName: data.filename)
            return try await Model.createItem(provider: importer, title: customName, note: note, labels: labels ?? [])
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

        func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let data: URL = if let url {
                url
            } else {
                try await $url.requestValue()
            }

            let p = NSItemProvider(object: data as NSURL)
            let importer = DataImporter(itemProvider: p)
            return try await Model.createItem(provider: importer, title: customName, note: note, labels: labels ?? [])
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

        func perform() async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
            let data: String = if let text {
                text
            } else {
                try await $text.requestValue()
            }

            let p = NSItemProvider(object: data as NSString)
            let importer = DataImporter(itemProvider: p)
            return try await Model.createItem(provider: importer, title: customName, note: note, labels: labels ?? [])
        }
    }

    static func processCreationResult(_ result: PasteResult) async throws -> some IntentResult & ReturnsValue<ArchivedItemEntity> & OpensIntent {
        switch result {
        case .noData:
            throw Error.noItemsCreated

        case let .success(items):
            guard let item = items.first else {
                throw Error.noItemsCreated
            }
            let entity = await ArchivedItemEntity(id: item.uuid, title: item.displayTitleOrUuid)
            let hi = OpenGladys()
            hi.entity = entity
            hi.action = .highlight
            for _ in 0 ..< 20 {
                let ongoing = await DropStore.ingestingItems
                if !ongoing { break }
                try? await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)
            }
            return .result(value: entity, opensIntent: hi)
        }
    }

    enum Error: Swift.Error, CustomLocalizedStringResourceConvertible {
        case noItemsCreated
        case itemNotFound
        case nothingInClipboard

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .noItemsCreated: "No items were created from this data"
            case .itemNotFound: "Item could not be found"
            case .nothingInClipboard: "There was nothing in the clipboard"
            }
        }
    }
}
