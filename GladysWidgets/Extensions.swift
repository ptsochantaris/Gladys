import AppIntents
import Foundation
import GladysCommon
import GladysUI
import WidgetKit
#if canImport(AppKit)
    import AppKit
#endif

extension ArchivedItem {
    func copyToPasteboard(donateShortcut _: Bool = true) {}
}

extension WidgetFamily {
    var colunms: CGFloat {
        switch self {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: 1
        case .systemSmall: 2
        case .systemMedium: 4
        case .systemLarge: 4
        case .systemExtraLarge: 8
        @unknown default: 1
        }
    }

    var rows: CGFloat {
        switch self {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: 1
        case .systemSmall: 2
        case .systemMedium: 2
        case .systemLarge: 4
        case .systemExtraLarge: 4
        @unknown default: 1
        }
    }

    var maxCount: Int {
        switch self {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: 1
        case .systemSmall: 4
        case .systemMedium: 8
        case .systemLarge: 16
        case .systemExtraLarge: 32
        @unknown default: 1
        }
    }
}

extension Model: WidgetModel {
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
