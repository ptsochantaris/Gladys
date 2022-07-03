import Cocoa

@MainActor
func genericAlert(title: String, message: String?, windowOverride _: NSWindow? = nil, buttonTitle _: String = "OK") async {
    await genericAlert(title: title, message: message)
}

@MainActor
func genericAlert(title: String, message: String?, windowOverride _: NSWindow? = nil, buttonTitle: String = "OK", offerSettingsShortcut _: Bool = false) {
    let a = NSAlert()
    a.messageText = title
    a.addButton(withTitle: buttonTitle)
    if let message = message {
        a.informativeText = message
    }

    a.runModal()
}
