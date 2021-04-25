//
//  WindowController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 24/04/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import Cocoa

var allFilters: [ModelFilterContext] {
    return NSApp.windows.compactMap {
        ($0.contentViewController as? ViewController)?.filter
    }
}

var keyGladysControllerIfExists: ViewController? {
    return NSApp.keyWindow?.contentViewController as? ViewController
}

extension NSWindow {
    var gladysController: ViewController? {
        return contentViewController as? ViewController
    }
    
    func hide() {
        orderOut(nil)
    }
}

struct WindowState: Codable {
    let frame: NSRect
    let search: String?
    let labels: [String]
}

func storeWindowStates() {
    let windowsToStore = NSApp.windows.compactMap { window -> WindowState? in
        if let c = window.contentViewController as? ViewController {
            let labels = c.filter.labelToggles.filter { $0.enabled }.map { $0.name }
            return WindowState(frame: window.frame, search: c.filter.text, labels: labels)
        }
        return nil
    }
    if let json = try? JSONEncoder().encode(windowsToStore) {
        PersistedOptions.defaults.setValue(json, forKey: "lastWindowStates")
    }
}

func restoreWindows() {
    let sb = NSStoryboard(name: "Main", bundle: nil)
    let id = NSStoryboard.SceneIdentifier("windowController")

    // migrate saved window position from previous version, if exists
    if let d = PersistedOptions.defaults.value(forKey: "lastWindowPosition") as? NSDictionary {
        PersistedOptions.defaults.removeObject(forKey: "lastWindowPosition")
        if let frame = NSRect(dictionaryRepresentation: d) {
            let state = WindowState(frame: frame, search: nil, labels: [])
            if let data = try? JSONEncoder().encode([state]) {
                PersistedOptions.defaults.setValue(data, forKey: "lastWindowStates")
            }
        }
    }
    
    if let data = PersistedOptions.defaults.data(forKey: "lastWindowStates"), let states = try? JSONDecoder().decode([WindowState].self, from: data) {
        for state in states {
            if let controller = sb.instantiateController(withIdentifier: id) as? WindowController, let g = controller.window?.gladysController {
                g.restoreState(from: state)
            }
        }

    } else {
        if let controller = sb.instantiateController(withIdentifier: id) as? WindowController, let w = controller.window {
            w.makeKeyAndOrderFront(nil)
        }
    }
}

final class WindowController: NSWindowController, NSWindowDelegate {
    private static var strongRefs = [WindowController]()

    override init(window: NSWindow?) {
        super.init(window: window)
        WindowController.strongRefs.append(self)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        WindowController.strongRefs.append(self)
    }
    
    var gladysController: ViewController {
        return contentViewController as! ViewController
    }
    
    func windowWillClose(_ notification: Notification) {
        Model.lockUnlockedItems()
        WindowController.strongRefs.removeAll { $0 === self }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        gladysController.isKey()
        Model.updateBadge()
    }

    func windowDidMove(_ notification: Notification) {
        storeWindowStates()
    }
    
    func windowWillStartLiveResize(_ notification: Notification) {
        gladysController.hideLabels()
    }
    
    func windowDidEndLiveResize(_ notification: Notification) {
        storeWindowStates()
    }    
}
