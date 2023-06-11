import GladysCommon
import UIKit

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

    var dragItem: UIDragItem {
        let i = UIDragItem(itemProvider: itemProvider)
        i.localObject = self
        return i
    }

    func copyToPasteboard(donateShortcut: Bool = true) {
        UIPasteboard.general.setItemProviders([itemProvider], localOnly: false, expirationDate: nil)
        if donateShortcut {
            donateCopyIntent()
        }
    }
}
