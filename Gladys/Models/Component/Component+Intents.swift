import Intents
import UIKit

extension Component {
    func copyToPasteboard(donateShortcut: Bool = true) {
        UIPasteboard.general.setItemProviders([itemProvider], localOnly: false, expirationDate: nil)
        if donateShortcut {
            donateCopyIntent()
        }
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

    private func donateCopyIntent() {
        let intent = CopyComponentIntent()
        let trimmed = trimmedName
        intent.suggestedInvocationPhrase = "Copy '\(trimmed)' from Gladys"
        intent.component = INObject(identifier: uuid.uuidString, display: trimmed)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.identifier = "copy-\(uuid.uuidString)"
        interaction.donate { error in
            if let error = error {
                log("Error donating component copy shortcut: \(error.localizedDescription)")
            } else {
                log("Donated copy shortcut")
            }
        }
    }

    func removeIntents() {
        INInteraction.delete(with: ["copy-\(uuid.uuidString)"]) { error in
            if let error = error {
                log("Copy intent for component could not be removed: \(error.localizedDescription)")
            } else {
                log("Copy intent for component removed")
            }
        }
    }
}
