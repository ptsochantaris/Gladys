import AppIntents
import Foundation
import GladysUI
import GladysCommon

// Stubs for methods that are in the widget but will actually run in the main app target

extension Model {
    @available(iOS 16, *)
    static func createItem(provider _: NSItemProvider, title _: String?, note _: String?, labels _: [GladysAppIntents.ArchivedItemLabel]) async throws -> some IntentResult & ReturnsValue<GladysAppIntents.ArchivedItemEntity> & OpensIntent {
        try await GladysAppIntents.processCreationResult(.noData)
    }

    @discardableResult
    static func pasteItems(from providers: [NSItemProvider], overrides: ImportOverrides?) -> PasteResult {
        .noData
    }
}
