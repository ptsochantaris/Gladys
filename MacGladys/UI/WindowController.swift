//
//  WindowController.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 24/04/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import Cocoa

var allFilters: [ModelFilterContext] {
    return NSApp.orderedWindows.compactMap {
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
        WindowController.storeStates()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        gladysController.isKey()
        Model.updateBadge()
    }

    func windowDidMove(_ notification: Notification) {
        if window?.isVisible == true {
            WindowController.storeStates()
        }
    }
    
    func windowWillStartLiveResize(_ notification: Notification) {
        gladysController.hideLabels()
    }
    
    func windowDidEndLiveResize(_ notification: Notification) {
        if window?.isVisible == true {
            WindowController.storeStates()
        }
    }
    
    struct State: Codable {
        let frame: NSRect
        let search: String?
        let labels: [String]
    }

    static func storeStates() {
        let windowsToStore = NSApp.orderedWindows.compactMap { window -> State? in
            if let c = window.contentViewController as? ViewController {
                let labels = c.filter.labelToggles.filter { $0.enabled }.map { $0.name }
                return State(frame: window.frame, search: c.filter.text, labels: labels)
            }
            return nil
        }
        if windowsToStore.isEmpty {
            log("Keeping last visible window position")
            return
        }
        if let json = try? JSONEncoder().encode(windowsToStore) {
            lastWindowStates = json
        } else {
            log("Warning: Could not persist window states!")
        }
    }

    static func restoreStates() {
        let sb = NSStoryboard(name: "Main", bundle: nil)
        let id = NSStoryboard.SceneIdentifier("windowController")

        // migrate saved window position from previous version, if exists
        if let d = lastWindowPosition {
            lastWindowPosition = nil
            if let frame = NSRect(dictionaryRepresentation: d) {
                let state = State(frame: frame, search: nil, labels: [])
                if let data = try? JSONEncoder().encode([state]) {
                    lastWindowStates = data
                }
            }
        }
        
        if let data = lastWindowStates, let states = try? JSONDecoder().decode([State].self, from: data) {
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
    
    static func openRecentWindow() -> Bool {
        let sb = NSStoryboard(name: "Main", bundle: nil)
        let id = NSStoryboard.SceneIdentifier("windowController")
        if let data = lastWindowStates,
           let states = try? JSONDecoder().decode([State].self, from: data),
           let state = states.first,
           let controller = sb.instantiateController(withIdentifier: id) as? WindowController,
           let g = controller.window?.gladysController {
            g.restoreState(from: state, forceVisibleNow: true)
            return true
        }
        return false
    }
    
    static var visibleItemWindows: [NSWindow] {
        return NSApp.orderedWindows.filter { $0.isVisible && ($0.contentViewController is ViewController) }
    }
    
    @OptionalUserDefault(key: "lastWindowStates", emptyValue: nil)
    static private var lastWindowStates: Data?
    
    @OptionalUserDefault(key: "lastWindowPosition", emptyValue: nil)
    static private var lastWindowPosition: NSDictionary?

}
