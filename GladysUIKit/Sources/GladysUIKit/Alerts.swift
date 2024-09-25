import Foundation
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
public func genericAlert(title: String?, message: String? = nil, buttonTitle: String? = "OK", offerSettingsShortcut: Bool = false, alertController: ((UIAlertController) -> Void)? = nil) async {
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
            Task {
                try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
                await a.dismiss(animated: true)
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
