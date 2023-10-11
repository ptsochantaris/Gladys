import AppIntents
import Foundation
import GladysCommon
import GladysUI
#if canImport(AppKit)
    import AppKit
#endif

// Stubs for methods that are in the widget but will actually run in the main app target

extension Model {
    @available(iOS 16, *)
    static func createItem(provider _: DataImporter, title _: String?, note _: String?, labels _: [GladysAppIntents.ArchivedItemLabel]) async throws -> some IntentResult & ReturnsValue<GladysAppIntents.ArchivedItemEntity> & OpensIntent {
        try await GladysAppIntents.processCreationResult(.noData)
    }

    #if canImport(AppKit)
        @discardableResult
        static func addItems(from _: NSPasteboard, at _: IndexPath, overrides _: ImportOverrides?, filterContext _: Filter?) -> PasteResult {
            .noData
        }
    #endif

    @discardableResult
    static func pasteItems(from _: [DataImporter], overrides _: ImportOverrides?) -> PasteResult {
        .noData
    }
}

extension ArchivedItem {
    func copyToPasteboard(donateShortcut _: Bool = true) {}
}
