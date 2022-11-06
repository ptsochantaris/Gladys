import UIKit

extension UIViewController {
    func addChildController(_ vc: UIViewController, to view: UIView) {
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(vc)
        view.addSubview(vc.view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: vc.view.topAnchor),
            view.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)
        ])
        vc.didMove(toParent: self)
    }

    func makeDoneButton(target: Any, action: Selector) -> UIBarButtonItem {
        let b = UIBarButtonItem(barButtonSystemItem: .close, target: target, action: action)
        b.accessibilityLabel = "Done"
        return b
    }

    func removeChildController(_ vc: UIViewController) {
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
    }

    var phoneMode: Bool {
        guard let t = (viewIfLoaded ?? navigationController?.viewIfLoaded)?.window?.traitCollection else { return false }
        return t.horizontalSizeClass == .compact || t.verticalSizeClass == .compact
    }

    var isHovering: Bool {
        (popoverPresentationController?.adaptivePresentationStyle.rawValue ?? 0) == -1
    }

    var isAccessoryWindow: Bool {
        (navigationController?.viewIfLoaded ?? viewIfLoaded)?.window?.windowScene?.isAccessoryWindow ?? false
    }

    func dismiss(animated: Bool) async {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                dismiss(animated: animated) {
                    continuation.resume()
                }
            }
        }
    }
}
