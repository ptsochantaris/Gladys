import UIKit

extension UIKeyCommand {
    static func makeCommand(input: String, modifierFlags: UIKeyModifierFlags, action: Selector, title: String) -> UIKeyCommand {
        let c = UIKeyCommand(input: input, modifierFlags: modifierFlags, action: action)
        c.title = title
        return c
    }
}

@MainActor
var currentWindow: UIWindow? {
    UIApplication.shared.connectedScenes.filter { $0.activationState != .background }.compactMap { ($0 as? UIWindowScene)?.windows.first }.lazy.first
}

@MainActor
weak var lastUsedWindow: UIWindow?

@MainActor
func genericAlert(title: String?, message: String?, autoDismiss: Bool = true, buttonTitle: String? = "OK", offerSettingsShortcut: Bool = false, alertController: ((UIAlertController) -> Void)? = nil) async {
    guard let presenter = currentWindow?.alertPresenter else {
        return
    }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if let buttonTitle {
            a.addAction(UIAlertAction(title: buttonTitle, style: .default) { _ in
                continuation.resume()
            })
        }

        if offerSettingsShortcut {
            a.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:])
                continuation.resume()
            })
        }

        presenter.present(a, animated: true)

        if buttonTitle == nil, autoDismiss {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
                await a.dismiss(animated: true)
                continuation.resume()
            }
        }

        alertController?(a)
    }
}

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
