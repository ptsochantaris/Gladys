import UIKit

extension UIKeyCommand {
    static func makeCommand(input: String, modifierFlags: UIKeyModifierFlags, action: Selector, title: String) -> UIKeyCommand {
        let c = UIKeyCommand(input: input, modifierFlags: modifierFlags, action: action)
        c.title = title
        return c
    }
}

@MainActor
weak var lastUsedWindow: UIWindow?

@MainActor
func getInput(from: UIViewController, title: String, action: String, previousValue: String?) async -> String? {
    await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
        let a = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        a.addTextField { textField in
            textField.placeholder = title
            textField.text = previousValue
        }
        a.addAction(UIAlertAction(title: action, style: .default) { _ in
            let result = a.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            continuation.resume(returning: result)
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            continuation.resume(returning: nil)
        })
        from.present(a, animated: true)
    }
}
