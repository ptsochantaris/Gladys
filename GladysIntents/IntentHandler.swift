import GladysCommon
import Intents
import UIKit

final class IntentHandler: INExtension, PasteClipboardIntentHandling, CopyItemIntentHandling, CopyComponentIntentHandling {
    @MainActor
    func handle(intent: CopyComponentIntent, completion: @escaping (CopyComponentIntentResponse) -> Void) {
        guard let uuidString = intent.component?.identifier else {
            completion(CopyComponentIntentResponse(code: .failure, userActivity: nil))
            return
        }

        guard let (_, component) = LiteModel.locateComponentWithoutLoading(uuid: uuidString) else {
            completion(CopyComponentIntentResponse(code: .failure, userActivity: nil))
            return
        }

        component.copyToPasteboard(donateShortcut: false)
        completion(CopyComponentIntentResponse(code: .success, userActivity: nil))
    }

    /////////////////////////////

    @MainActor
    func handle(intent: CopyItemIntent, completion: @escaping (CopyItemIntentResponse) -> Void) {
        guard let uuidString = intent.item?.identifier, let uuid = UUID(uuidString: uuidString) else {
            completion(CopyItemIntentResponse(code: .failure, userActivity: nil))
            return
        }

        guard let item = LiteModel.locateItemWithoutLoading(uuid: uuid.uuidString) else {
            completion(CopyItemIntentResponse(code: .failure, userActivity: nil))
            return
        }

        item.copyToPasteboard(donateShortcut: false)
        completion(CopyItemIntentResponse(code: .success, userActivity: nil))
    }

    /////////////////////////////

    func confirm(intent _: CopyItemIntent, completion: @escaping (CopyItemIntentResponse) -> Void) {
        completion(CopyItemIntentResponse(code: .ready, userActivity: nil))
    }

    func confirm(intent _: CopyComponentIntent, completion: @escaping (CopyComponentIntentResponse) -> Void) {
        completion(CopyComponentIntentResponse(code: .ready, userActivity: nil))
    }

    func confirm(intent _: PasteClipboardIntent, completion: @escaping (PasteClipboardIntentResponse) -> Void) {
        completion(PasteClipboardIntentResponse(code: .ready, userActivity: nil))
    }

    func handle(intent _: PasteClipboardIntent, completion: @escaping (PasteClipboardIntentResponse) -> Void) {
        let activity = NSUserActivity(activityType: kGladysStartPasteShortcutActivity)
        completion(PasteClipboardIntentResponse(code: .continueInApp, userActivity: activity))
    }
}
