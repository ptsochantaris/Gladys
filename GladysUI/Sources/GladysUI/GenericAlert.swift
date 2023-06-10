#if os(macOS)
    import Cocoa

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

#else
    import UIKit

    public extension UIWindow {
        var alertPresenter: UIViewController? {
            var vc = rootViewController
            while let p = vc?.presentedViewController {
                if p is UIAlertController {
                    break
                }
                vc = p
            }
            return vc
        }
    }

    @MainActor
    public var currentWindow: UIWindow? {
        UIApplication.shared.connectedScenes.filter { $0.activationState != .background }.compactMap { ($0 as? UIWindowScene)?.windows.first }.lazy.first
    }

    @MainActor
    public func genericAlert(title: String?, message: String?, buttonTitle: String? = "OK", offerSettingsShortcut: Bool = false, alertController: ((UIAlertController) -> Void)? = nil) async {
        guard let presenter = currentWindow?.alertPresenter else {
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let a = GladysAlertController(title: title, message: message, preferredStyle: .alert)
            if let buttonTitle {
                a.addAction(UIAlertAction(title: buttonTitle, style: .default, handler: nil))
            }

            if offerSettingsShortcut {
                a.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:])
                })
            }

            a.completion = { continuation.resume() }

            presenter.present(a, animated: true)

            if buttonTitle == nil {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
                    a.dismiss(animated: true)
                }
            }

            alertController?(a)
        }
    }

    final class GladysAlertController: UIAlertController {
        var completion: (() -> Void)?

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            completion?()
        }
    }
#endif
