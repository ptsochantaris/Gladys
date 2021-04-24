//
//  WindowController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 24/04/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import Cocoa

final class WindowController: NSWindowController, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        Model.lockUnlockedItems()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        ViewController.shared.isKey()
    }

    func windowDidMove(_ notification: Notification) {
        if let w = window, w.isVisible {
            lastWindowPosition = w.frame
        }
    }

    func windowDidResize(_ notification: Notification) {
        if let w = window, w.isVisible {
            lastWindowPosition = w.frame
            ViewController.shared.hideLabels()
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        ViewController.shared.collection.reloadData()
    }

    var lastWindowPosition: NSRect? {
        get {
            if let d = PersistedOptions.defaults.value(forKey: "lastWindowPosition") as? NSDictionary {
                return NSRect(dictionaryRepresentation: d)
            } else {
                return nil
            }
        }
        set {
            PersistedOptions.defaults.setValue(newValue?.dictionaryRepresentation, forKey: "lastWindowPosition")
        }
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        if let f = lastWindowPosition {
            window?.setFrame(f, display: false)
        }
    }

    private var firstShow = true
    override func showWindow(_ sender: Any?) {
        if firstShow && PersistedOptions.hideMainWindowAtStartup {
            return
        }
        firstShow = false
        super.showWindow(sender)
    }
}
