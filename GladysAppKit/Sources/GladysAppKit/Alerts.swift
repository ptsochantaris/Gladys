import AppKit
import Foundation

@MainActor
public func genericAlert(title: String, message: String?, windowOverride _: NSWindow? = nil, buttonTitle: String = "OK", offerSettingsShortcut _: Bool = false) async {
    let a = NSAlert()
    a.messageText = title
    _ = a.addButton(withTitle: buttonTitle)
    if let message {
        a.informativeText = message
    }
    _ = a.runModal()
}
