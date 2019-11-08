//
//  UIViewController+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit

extension UIWindowScene {
    var isInStandaloneWindow: Bool {
        return session.stateRestorationActivity != nil
    }
}

func makeDoneButton(target: Any, action: Selector) -> UIBarButtonItem {
    let b = UIBarButtonItem(barButtonSystemItem: .close, target: target, action: action)
    b.accessibilityLabel = "Done"
    return b
}

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

    func removeChildController(_ vc: UIViewController) {
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
    }
}
