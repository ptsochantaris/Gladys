import GladysCommon
import UIKit

extension Component {
    func copyToPasteboard() {
        UIPasteboard.general.setItemProviders([itemProvider], localOnly: false, expirationDate: nil)
    }

    var itemProvider: NSItemProvider {
        let p = NSItemProvider()
        p.suggestedName = trimmedSuggestedName
        if PersistedOptions.requestInlineDrops {
            p.preferredPresentationStyle = .inline
        }
        register(with: p)
        return p
    }

    var trimmedName: String {
        oneTitle.truncateWithEllipses(limit: 32)
    }

    var trimmedSuggestedName: String {
        oneTitle.truncateWithEllipses(limit: 128)
    }
}
