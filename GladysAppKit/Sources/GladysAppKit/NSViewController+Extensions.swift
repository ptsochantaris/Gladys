import AppKit
import Foundation

public extension NSViewController {
    func addChildController(_ vc: NSViewController, to container: NSView, insets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)) {
        let viewBeingAdded = vc.view
        viewBeingAdded.translatesAutoresizingMaskIntoConstraints = false
        addChild(vc)
        if let stackView = container as? NSStackView {
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
        if userActivity == nil, let childActivity = vc.userActivity {
            userActivity = childActivity
        }
    }

    func removeChildController(_ vc: NSViewController) {
        vc.view.removeFromSuperview()
        vc.removeFromParent()
    }
}
