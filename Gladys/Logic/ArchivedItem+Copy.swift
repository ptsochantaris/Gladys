import GladysCommon
import UIKit
#if MAINAPP
    import Intents
#endif

extension ArchivedItem {
    private var itemProvider: NSItemProvider {
        let p = NSItemProvider()
        p.suggestedName = trimmedSuggestedName
        if PersistedOptions.requestInlineDrops {
            p.preferredPresentationStyle = .inline
        }
        components.forEach { $0.register(with: p) }
        return p
    }

    #if !INTENTSEXTENSION
        var dragItem: UIDragItem {
            let i = UIDragItem(itemProvider: itemProvider)
            i.localObject = self
            return i
        }
    #endif

    func copyToPasteboard(donateShortcut: Bool = true) {
        UIPasteboard.general.setItemProviders([itemProvider], localOnly: false, expirationDate: nil)
        if donateShortcut {
            donateCopyIntent()
        }
    }

    #if MAINAPP
        var copyIntent: CopyItemIntent {
            let intent = CopyItemIntent()
            let trimmed = displayTitleOrUuid.truncateWithEllipses(limit: 24)
            intent.suggestedInvocationPhrase = "Copy '\(trimmed)' from Gladys"
            intent.item = INObject(identifier: uuid.uuidString, display: trimmed)
            return intent
        }
    #endif

    func donateCopyIntent() {
        #if MAINAPP
            if #available(iOS 16, *) {
                log("Will not donate SiriKit copy shortcut")
            } else {
                let interaction = INInteraction(intent: copyIntent, response: nil)
                interaction.identifier = "copy-\(uuid.uuidString)"
                interaction.donate { error in
                    if let error {
                        log("Error donating copy shortcut: \(error.localizedDescription)")
                    } else {
                        log("Donated copy shortcut")
                    }
                }
            }
        #endif
    }
}
