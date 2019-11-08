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
