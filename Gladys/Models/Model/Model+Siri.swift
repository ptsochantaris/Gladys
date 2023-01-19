import Foundation
import GladysCommon
import Intents
import UIKit

extension Model {
    static var pasteIntent: PasteClipboardIntent {
        let intent = PasteClipboardIntent()
        intent.suggestedInvocationPhrase = "Paste in Gladys"
        return intent
    }

    static func clearLegacyIntents() {
        if #available(iOS 16, *) {
            INInteraction.deleteAll() // using app intents now
        }
    }

    static func donatePasteIntent() {
        if #available(iOS 16, *) {
            log("Will not donate SiriKit paste shortcut")
        } else {
            let interaction = INInteraction(intent: pasteIntent, response: nil)
            interaction.identifier = "paste-in-gladys"
            interaction.donate { error in
                if let error {
                    log("Error donating paste shortcut: \(error.localizedDescription)")
                } else {
                    log("Donated paste shortcut")
                }
            }
        }
    }
}
