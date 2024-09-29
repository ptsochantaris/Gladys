#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif
import AppIntents
import GladysCommon
import GladysUI

extension GladysAppIntents {
    struct PasteIntoGladys: AppIntent {
        static var title: LocalizedStringResource { "Paste from clipboard" }

        static let openAppWhenRun = true

        func perform() async throws -> some IntentResult {
            let topIndex = IndexPath(item: 0, section: 0)
            #if canImport(UIKit)
                guard let p = UIPasteboard.general.itemProviders.first else {
                    throw GladysAppIntentsError.nothingInClipboard
                }
                let importer = DataImporter(itemProvider: p)
                await Model.pasteItems(from: [importer], overrides: nil)
            #else
                let pb = NSPasteboard.general
                guard let c = pb.pasteboardItems?.count, c > 0 else {
                    throw GladysAppIntentsError.nothingInClipboard
                }
                _ = await Model.addItems(from: pb, at: topIndex, overrides: .none, filterContext: nil)
            #endif
            return .result()
        }
    }
}
