//
//  GenericAlert.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 24/04/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import Cocoa

@MainActor
func genericAlert(title: String, message: String?, windowOverride _: NSWindow? = nil, buttonTitle: String = "OK", offerSettingsShortcut _: Bool = false, completion: (() -> Void)? = nil) {
    let a = NSAlert()
    a.messageText = title
    a.addButton(withTitle: buttonTitle)
    if let message = message {
        a.informativeText = message
    }

    a.runModal()
    completion?()
}
