//
//  GenericAlert.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 24/04/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import Cocoa

func genericAlert(title: String, message: String?, windowOverride: NSWindow? = nil, buttonTitle: String = "OK", offerSettingsShortcut: Bool = false, completion: (() -> Void)? = nil) {

    var finalVC: NSViewController = ViewController.shared
    while let newVC = finalVC.presentedViewControllers?.first(where: { $0.view.window != nil }) {
        finalVC = newVC
    }

    let a = NSAlert()
    a.messageText = title
    a.addButton(withTitle: buttonTitle)
    if let message = message {
        a.informativeText = message
    }
    
    a.runModal()
    completion?()
}
