import AppIntents
import Foundation
import GladysCommon
import GladysUI

extension GladysAppIntents {
    struct DeleteItem: AppIntent, UndoableIntent {
        @Parameter(title: "Item")
        var entity: ArchivedItemEntity?

        static var title: LocalizedStringResource {
            "Delete item"
        }

        @MainActor
        func perform() async throws -> some IntentResult {
            guard let entity,
                  let item = DropStore.item(uuid: entity.id)
            else {
                throw GladysAppIntentsError.itemNotFound
            }

            try await requestConfirmation(dialog: "Delete \"\(item.trimmedName)\"?")

            // The item's files are purged on save, so capture what's needed to restore it beforehand.
            // Locked item contents are never snapshotted.
            if !item.isLocked, let snapshot = DeletedItemSnapshot(item: item) {
                undoManager?.registerUndo(withTarget: snapshot) { $0.restore() }
            }

            Model.delete(items: [item])
            return .result()
        }
    }

    /// An in-memory copy of a deleted item's data, re-imported as a new item on undo
    @MainActor
    private final class DeletedItemSnapshot {
        private let importers: [DataImporter]
        private let overrides: ImportOverrides

        init?(item: ArchivedItem) {
            let importers = item.components.compactMap { component -> DataImporter? in
                guard let data = component.bytes else { return nil }
                return DataImporter(type: component.typeIdentifier, data: data, suggestedName: item.suggestedName)
            }
            if importers.isEmpty {
                return nil
            }
            self.importers = importers
            overrides = ImportOverrides(title: item.titleOverride.isEmpty ? nil : item.titleOverride,
                                        note: item.note.isEmpty ? nil : item.note,
                                        labels: item.labels)
        }

        func restore() {
            #if canImport(UIKit)
                _ = Model.pasteItems(from: importers, overrides: overrides, currentFilter: nil)
            #else
                _ = Model.addItems(itemProviders: importers, indexPath: IndexPath(item: 0, section: 0), overrides: overrides, filterContext: nil)
            #endif
        }
    }
}
