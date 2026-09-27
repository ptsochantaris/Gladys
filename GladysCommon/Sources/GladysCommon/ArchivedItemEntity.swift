#if !os(watchOS)
    import AppIntents
    import CoreSpotlight
    import Foundation

    /// Exposes the App Intents types declared in this package to the apps that include it.
    public struct GladysCommonIntentsPackage: AppIntentsPackage {}

    public struct ArchivedItemEntity: IndexedEntity, Identifiable {
        public let id: UUID

        @Property(title: "Title", indexingKey: \.title)
        public var title: String

        @Property(title: "Note", indexingKey: \.contentDescription)
        public var note: String

        @Property(title: "Labels", indexingKey: \.keywords)
        public var labels: [String]

        @Property(title: "Text", indexingKey: \.textContent)
        public var text: String

        @Property(title: "Link")
        public var url: URL?

        @Property(title: "Created", indexingKey: \.addedDate)
        public var createdAt: Date?

        @Property(title: "Updated", indexingKey: \.contentModificationDate)
        public var updatedAt: Date?

        private let thumbnailURL: URL?
        private let thumbnailIsTemplate: Bool

        /// Which kinds of content this item can hand over to other apps, see ArchivedItemEntity+Transferable
        let exportableContent: ExportableContent

        public static let defaultQuery = ArchivedItemQuery()

        public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Gladys Item"

        public var displayRepresentation: DisplayRepresentation {
            let subtitle = note.isEmpty ? url?.absoluteString : note
            return DisplayRepresentation(title: "\(title)",
                                         subtitle: subtitle.map { "\($0)" },
                                         image: thumbnailURL.map { .init(url: $0, isTemplate: thumbnailIsTemplate) })
        }

        /// A reference-only entity, for when just the identifier is known (e.g. widget buttons)
        public init(id: UUID) {
            // plain stored properties must be set before the @Property wrappers
            self.id = id
            thumbnailURL = nil
            thumbnailIsTemplate = false
            exportableContent = []
            title = ""
            note = ""
            labels = []
            text = ""
            url = nil
            createdAt = nil
            updatedAt = nil
        }

        @MainActor
        public init(item: ArchivedItem) {
            let locked = item.isLocked
            id = item.uuid
            thumbnailURL = locked ? nil : item.imagePath
            thumbnailIsTemplate = item.highestPriorityIconItem?.displayIconTemplate ?? false
            exportableContent = locked ? [] : ExportableContent(item: item)
            createdAt = item.createdAt
            updatedAt = item.updatedAt
            if locked {
                // Never expose the contents of a locked item
                title = item.lockHint ?? "Locked Item"
                note = ""
                labels = []
                text = ""
                url = nil
            } else {
                title = item.displayTitleOrUuid
                note = item.note
                labels = item.labels
                text = item.displayText.0 ?? ""
                url = item.associatedWebURL
            }
        }
    }

    public nonisolated struct ArchivedItemQuery: EntityStringQuery {
        /// Set by the full apps to route text matching through their Spotlight-backed filtering
        @MainActor
        public static var textSearchProvider: ((String) -> [ArchivedItem])?

        public init() {}

        public func entities(matching string: String) async throws -> [ArchivedItemEntity] {
            await MainActor.run {
                let matches: [ArchivedItem] = if let provider = Self.textSearchProvider {
                    provider(string)
                } else {
                    DropStore.allDrops.filter { item in
                        !item.isLocked && (item.displayTitleOrUuid.localizedCaseInsensitiveContains(string)
                            || item.note.localizedCaseInsensitiveContains(string)
                            || item.labels.contains { $0.localizedCaseInsensitiveContains(string) })
                    }
                }
                return matches.map { ArchivedItemEntity(item: $0) }
            }
        }

        public func entities(for identifiers: [ArchivedItemEntity.ID]) async throws -> [ArchivedItemEntity] {
            await MainActor.run {
                identifiers.compactMap { DropStore.item(uuid: $0) }.map { ArchivedItemEntity(item: $0) }
            }
        }

        public func suggestedEntities() async throws -> [ArchivedItemEntity] {
            await MainActor.run {
                DropStore.allDrops.map { ArchivedItemEntity(item: $0) }
            }
        }
    }
#endif
