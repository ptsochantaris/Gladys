import Foundation
import Intents

extension Model {
    static var pasteIntent: PasteClipboardIntent {
        let intent = PasteClipboardIntent()
        intent.suggestedInvocationPhrase = "Paste in Gladys"
        return intent
    }

    static func donatePasteIntent() {
        let interaction = INInteraction(intent: pasteIntent, response: nil)
        interaction.identifier = "paste-in-gladys"
        interaction.donate { error in
            if let error = error {
                log("Error donating paste shortcut: \(error.localizedDescription)")
            } else {
                log("Donated paste shortcut")
                PersistedOptions.pasteShortcutAutoDonated = true
            }
        }
    }
}
