import Cocoa

@MainActor
func genericAlert(title: String, message: String?, windowOverride _: NSWindow? = nil, buttonTitle: String = "OK", offerSettingsShortcut _: Bool = false) async {
    let a = NSAlert()
    a.messageText = title
    a.addButton(withTitle: buttonTitle)
    if let message = message {
        a.informativeText = message
    }

    a.runModal()
}
