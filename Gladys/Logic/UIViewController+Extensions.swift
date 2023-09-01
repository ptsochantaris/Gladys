import UIKit

extension UIViewController {
    func addChildController(_ vc: UIViewController, to container: UIView, insets: UIEdgeInsets = .zero) {
        guard let viewBeingAdded = vc.view else { return }
        viewBeingAdded.translatesAutoresizingMaskIntoConstraints = false
        addChild(vc)
        if let stackView = container as? UIStackView {
            stackView.addArrangedSubview(viewBeingAdded)
        } else {
            container.addSubview(vc.view)
            NSLayoutConstraint.activate([
                viewBeingAdded.topAnchor.constraint(equalTo: container.topAnchor, constant: -insets.top),
                viewBeingAdded.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: insets.bottom),
                viewBeingAdded.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: -insets.left),
                viewBeingAdded.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: insets.right)
            ])
        }
        vc.didMove(toParent: self)
        if userActivity == nil, let childActivity = vc.userActivity {
            userActivity = childActivity
        }
    }

    func removeChildController(_ vc: UIViewController) {
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
    }

    func segue(_ name: String, sender: Any?) {
        performSegue(withIdentifier: name, sender: sender)
    }

    func makeDoneButton(target: Any, action: Selector) -> UIBarButtonItem {
        let b = UIBarButtonItem(barButtonSystemItem: .close, target: target, action: action)
        b.accessibilityLabel = "Done"
        return b
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
