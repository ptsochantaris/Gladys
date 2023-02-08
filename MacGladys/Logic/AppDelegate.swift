import CloudKit
import Cocoa
import CoreSpotlight
import GladysCommon
import GladysUI
import HotKey
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private static var hotKey: HotKey?

    static func updateHotkey() {
        hotKey = nil

        let hotKeyCode = PersistedOptions.hotkeyChar
        let enable = hotKeyCode >= 0 && (PersistedOptions.hotkeyCmd || PersistedOptions.hotkeyOption || PersistedOptions.hotkeyCtrl)
        if enable {
            var modifiers = NSEvent.ModifierFlags()
            if PersistedOptions.hotkeyOption { modifiers = modifiers.union(.option) }
            if PersistedOptions.hotkeyShift { modifiers = modifiers.union(.shift) }
            if PersistedOptions.hotkeyCtrl { modifiers = modifiers.union(.control) }
            if PersistedOptions.hotkeyCmd { modifiers = modifiers.union(.command) }
            let h = HotKey(carbonKeyCode: UInt32(hotKeyCode), carbonModifiers: modifiers.carbonFlags)
            h.keyDownHandler = {
                let visibleItemWindows = WindowController.visibleItemWindows
                let visibleItemWindowsCount = visibleItemWindows.count
                let allItemWindowCount = NSApp.orderedWindows.reduce(0) { $1.contentViewController is ViewController ? $0 + 1 : $0 }
                if visibleItemWindowsCount > 0, visibleItemWindowsCount == allItemWindowCount {
                    visibleItemWindows.forEach { $0.orderOut(nil) }
                } else {
                    (NSApp.delegate as? AppDelegate)?.focus()
                }
            }
            hotKey = h
        }
    }

    private var statusItem: NSStatusItem?

    @IBOutlet private var gladysMenuItem: NSMenuItem!
    @IBOutlet private var fileMenuItem: NSMenuItem!
    @IBOutlet private var editMenuItem: NSMenuItem!
    @IBOutlet private var itemMenuItem: NSMenuItem!
    @IBOutlet private var windowMenuItem: NSMenuItem!
    @IBOutlet private var helpMenuItem: NSMenuItem!

    private var menu: NSMenu {
        let m = NSMenu(title: "Gladys")
        m.addItem(gladysMenuItem.copy() as! NSMenuItem)
        m.addItem(fileMenuItem.copy() as! NSMenuItem)
        m.addItem(editMenuItem.copy() as! NSMenuItem)
        m.addItem(itemMenuItem.copy() as! NSMenuItem)
        m.addItem(windowMenuItem.copy() as! NSMenuItem)
        m.addItem(helpMenuItem.copy() as! NSMenuItem)
        return m
    }

    @objc private func statusBarItemSelected() {
        if NSApp.isActive, keyGladysControllerIfExists?.view.window?.isVisible ?? false {
            statusItem?.menu?.popUp(positioning: nil, at: .zero, in: nil)
        } else {
            focus()
        }
    }

    func updateMenubarIconMode(showing: Bool, forceUpdateMenu: Bool) {
        if PersistedOptions.menubarIconMode {
            if NSApp.activationPolicy() != .accessory {
                log("Changing activation policy to accessory mode")
                NSApp.setActivationPolicy(.accessory)
                Task { @MainActor in
                    NSApp.activate(ignoringOtherApps: true)
                    NSMenu.setMenuBarVisible(true)
                }
            }

            let s: NSStatusItem
            if let existingStatusItem = statusItem {
                s = existingStatusItem
            } else {
                s = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                s.button?.image = #imageLiteral(resourceName: "menubarIcon")
                statusItem = s
                log("Creating menubar status item")
            }

            if showing {
                if s.menu == nil || forceUpdateMenu {
                    s.button?.action = nil
                    s.menu = menu
                    log("Updating status item menu")
                }
            } else {
                if s.button?.action == nil {
                    s.menu = nil
                    s.button?.action = #selector(statusBarItemSelected)
                    log("Status item watching for click")
                }
            }

        } else if NSApp.activationPolicy() != .regular {
            log("Changing activation policy to regular mode")
            NSApp.setActivationPolicy(.regular)
            if let s = statusItem {
                log("Clearing status item")
                NSStatusBar.system.removeStatusItem(s)
                statusItem = nil
            }
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                NSMenu.setMenuBarVisible(true)
            }
        }
    }

    func application(_: NSApplication, openFiles filenames: [String]) {
        if filenames.count == 1, let name = filenames.first, name.hasSuffix(".gladysArchive") == true {
            let a = NSAlert()
            a.messageText = "Import items from this archive?"
            a.informativeText = "This is an archive of Gladys items that was previously exported. Would you like to import the items inside this archive to your current collection?"
            a.addButton(withTitle: "Cancel")
            a.addButton(withTitle: "Import Items")
            let response = a.runModal()
            switch response.rawValue {
            case 1000:
                log("Cancelled")
            default:
                let url = URL(fileURLWithPath: name)
                proceedWithImport(from: url)
            }
        } else {
            Task { @MainActor in
                Model.importFiles(paths: filenames, filterContext: keyGladysControllerIfExists?.filter)
            }
        }
    }

    final class ServicesProvider: NSObject {
        var urlEventBeforeLaunch = false

        @MainActor
        @objc private func handleServices(_ pboard: NSPasteboard, userData _: String, error _: AutoreleasingUnsafeMutablePointer<NSString>) {
            _ = Model.addItems(from: pboard, at: IndexPath(item: 0, section: 0), overrides: nil, filterContext: nil)
        }

        @MainActor
        @objc func handleURLEvent(event: NSAppleEventDescriptor, replyEvent _: NSAppleEventDescriptor) {
            if PersistedOptions.blockGladysUrlRequests { return }
            if let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: urlString) {
                urlEventBeforeLaunch = true
                _ = CallbackSupport.handlePossibleCallbackURL(url: url)
            }
        }
    }

    private let servicesProvider = ServicesProvider()
    static var shared: AppDelegate?

    private func migrateDefaults() {
        if PersistedOptions.defaultsVersion < 1 {
            if PersistedOptions.launchAtLogin {
                PersistedOptions.launchAtLogin = true
            }
            PersistedOptions.defaultsVersion = 1
        }
    }

    private func createNewWindow() {
        let controller = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("windowController")) as! WindowController
        if let w = controller.window {
            w.gladysController?.showWindow(window: w)
        }
    }

    @IBAction private func newWindowSelected(_: Any?) {
        if !NSApp.orderedWindows.isEmpty {
            createNewWindow()
        } else if !WindowController.openRecentWindow() {
            createNewWindow()
        }
        updateMenubarIconMode(showing: true, forceUpdateMenu: false)
    }

    @MainActor
    override init() {
        super.init()

        AppDelegate.shared = self

        migrateDefaults()

        LauncherCommon.killHelper()

        Model.setup()
        Model.registerStateHandler()
        Model.badgeHandler = {
            Task {
                if await CloudManager.showNetwork {
                    log("Updating app badge to show network")
                    NSApp.dockTile.badgeLabel = "↔"
                } else if PersistedOptions.badgeIconWithItemCount {
                    let count: Int
                    if let k = NSApp.keyWindow?.contentViewController as? ViewController {
                        count = k.filter.filteredDrops.count
                        log("Updating app badge to show current key window item count (\(count))")
                    } else if NSApp.orderedWindows.count == 1, let k = NSApp.orderedWindows.first(where: { $0.contentViewController is ViewController })?.gladysController {
                        count = k.filter.filteredDrops.count
                        log("Updating app badge to show current only window item count (\(count))")
                    } else {
                        count = DropStore.allDrops.count
                        log("Updating app badge to show item count (\(count))")
                    }
                    NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
                } else {
                    log("Updating app badge to clear")
                    NSApp.dockTile.badgeLabel = nil
                }
            }
        }

        CallbackSupport.setupCallbackSupport()
    }

    @MainActor
    func applicationWillFinishLaunching(_: Notification) {
        let s = NSAppleEventManager.shared()
        s.setEventHandler(servicesProvider,
                          andSelector: #selector(ServicesProvider.handleURLEvent(event:replyEvent:)),
                          forEventClass: AEEventClass(kInternetEventClass),
                          andEventID: AEEventID(kAEGetURL))

        NSApplication.shared.servicesProvider = servicesProvider

        for sortOption in SortOption.options {
            sortAscendingMenu.addItem(withTitle: sortOption.ascendingTitle, action: #selector(sortOptionSelected(_:)), keyEquivalent: "")
            sortDescendingMenu.addItem(withTitle: sortOption.descendingTitle, action: #selector(sortOptionSelected(_:)), keyEquivalent: "")
        }

        NSApplication.shared.registerForRemoteNotifications(matching: [])
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .provisional]) { granted, error in
            if let error {
                log("Notification permissions error: \(error.localizedDescription)")
            } else {
                log("Notification permissions request result: \(granted)")
            }
        }

        if PersistedOptions.badgeIconWithItemCount {
            Model.updateBadge()
        }

        Task {
            if await CloudManager.syncSwitchedOn {
                try? await CloudManager.sync()
            }
        }

        setupClipboardSnooping()

        Task {
            for await _ in NotificationCenter.default.notifications(named: .ClipboardSnoopingChanged) {
                setupClipboardSnooping()
            }
        }

        Task {
            for await _ in NotificationCenter.default.notifications(named: .AcceptStarting) {
                startProgress(for: nil, titleOverride: "Accepting Share…")
            }
        }

        Task {
            for await _ in NotificationCenter.default.notifications(named: .AcceptEnding) {
                endProgress()
            }
        }

        DistributedNotificationCenter.default.addObserver(self, selector: #selector(interfaceModeChanged(sender:)), name: NSNotification.Name(rawValue: "AppleInterfaceThemeChangedNotification"), object: nil)
    }

    @objc private func interfaceModeChanged(sender _: NSNotification) {
        Task { @MainActor in
            Images.shared.reset()
            sendNotification(name: .ItemCollectionNeedsDisplay, object: true)
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppDelegate.updateHotkey()

        let wn = NSWorkspace.shared.notificationCenter
        wn.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)

        NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = true

        Task {
            Model.startMonitoringForExternalChangesToBlobs()
        }

        if WindowController.restoreStates() {
            if PersistedOptions.hideMainWindowAtStartup || PersistedOptions.autoShowFromEdge > 0 {
                NSApp.activate(ignoringOtherApps: true)
                updateMenubarIconMode(showing: false, forceUpdateMenu: false)
                WindowController.visibleItemWindows.forEach { $0.orderOut(nil) }
            } else {
                focus()
            }
        } else {
            if !PersistedOptions.hideMainWindowAtStartup {
                newWindowSelected(nil)
            }
        }
    }

    @MainActor
    func applicationDidResignActive(_: Notification) {
        updateMenubarIconMode(showing: false, forceUpdateMenu: false)
        Model.trimTemporaryDirectory()
        if PersistedOptions.autoShowWhenDragging || PersistedOptions.autoShowFromEdge > 0 {
            WindowController.visibleItemWindows.forEach {
                $0.gladysController?.hideWindowBecauseOfMouse(window: $0)
            }
        }
    }

    @objc private func systemDidWake() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1000 * NSEC_PER_MSEC)
            AppDelegate.updateHotkey()
            do {
                try await CloudManager.opportunisticSyncIfNeeded()
            } catch {
                log("Error in system wake triggered sync: \(error.finalDescription)")
            }
        }
    }

    @MainActor
    func application(_: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task {
            await CloudManager.received(notificationInfo: userInfo)
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        focus()
        return false
    }

    func applicationShouldOpenUntitledFile(_: NSApplication) -> Bool {
        false
    }

    private func focus() {
        NSApp.activate(ignoringOtherApps: true)
        let windows = NSApp.orderedWindows
        if windows.isEmpty {
            newWindowSelected(nil)
        } else {
            windows.forEach {
                $0.gladysController?.showWindow(window: $0)
            }
        }
        updateMenubarIconMode(showing: true, forceUpdateMenu: false)
    }

    func application(_: NSApplication, continue userActivity: NSUserActivity, restorationHandler _: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        if userActivity.activityType == CSSearchableItemActionType {
            if let itemIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                focus()
                let request = HighlightRequest(uuid: itemIdentifier, extraAction: .none)
                Task { @MainActor in
                    sendNotification(name: .HighlightItemRequested, object: request)
                }
            }
            return true

        } else if userActivity.activityType == CSQueryContinuationActionType {
            if let searchQuery = userActivity.userInfo?[CSSearchQueryString] as? String {
                focus()
                keyGladysControllerIfExists?.startSearch(initialText: searchQuery)
            }
            return true

        } else if userActivity.activityType == kGladysDetailViewingActivity {
            if let uuid = userActivity.userInfo?[kGladysDetailViewingActivityItemUuid] as? UUID {
                focus()
                let request = HighlightRequest(uuid: uuid.uuidString, extraAction: .detail)
                Task { @MainActor in
                    sendNotification(name: .HighlightItemRequested, object: request)
                }
            } else if let uuidString = userActivity.userInfo?[kGladysDetailViewingActivityItemUuid] as? String {
                focus()
                let request = HighlightRequest(uuid: uuidString, extraAction: .detail)
                Task { @MainActor in
                    sendNotification(name: .HighlightItemRequested, object: request)
                }
            }
            return true

        } else if userActivity.activityType == kGladysQuicklookActivity {
            if let userInfo = userActivity.userInfo, let uuidString = userInfo[kGladysDetailViewingActivityItemUuid] as? String {
                focus()
                let childUuid = userInfo[kGladysDetailViewingActivityItemTypeUuid] as? String
                let request = HighlightRequest(uuid: uuidString, extraAction: .preview(childUuid))
                Task { @MainActor in
                    sendNotification(name: .HighlightItemRequested, object: request)
                }
            }
            return true
        }

        return false
    }

    @MainActor
    func application(_: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @CloudActor in
            CloudManager.apnsUpdate(deviceToken)
        }
    }

    @MainActor
    func application(_: NSApplication, didFailToRegisterForRemoteNotificationsWithError _: Error) {
        Task { @CloudActor in
            CloudManager.apnsUpdate(nil)
        }
    }

    func applicationWillResignActive(_: Notification) {
        Task { @MainActor in
            DropStore.clearCaches()
        }
    }

    func applicationWillTerminate(_: Notification) {
        WindowController.storeStates()
    }

    func applicationWillHide(_: Notification) {
        WindowController.storeStates()
    }

    @IBAction private func aboutSelected(_ sender: NSMenuItem) {
        if let about = NSApp.orderedWindows.first(where: { $0.contentViewController is AboutViewController }) {
            about.makeKeyAndOrderFront(sender)
            return
        }
        let controller = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "about") as! NSWindowController
        if let w = controller.window {
            w.makeKeyAndOrderFront(sender)
        }
    }

    @IBAction private func openWebSite(_: Any) {
        NSWorkspace.shared.open(URL(string: "https://www.bru.build/gladys-for-macos")!)
    }

    /////////////////////////////////////////////////////////////////

    private var pasteboardObservationTimer: Timer?
    private var pasteboardObservationCount = NSPasteboard.general.changeCount

    private func setupClipboardSnooping() {
        let snoop = PersistedOptions.clipboardSnooping

        if snoop, pasteboardObservationTimer == nil {
            let pasteboard = NSPasteboard.general
            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                let newCount = pasteboard.changeCount
                guard let s = self, s.pasteboardObservationCount != newCount else {
                    return
                }
                s.pasteboardObservationCount = newCount
                if let text = pasteboard.string(forType: .string), PersistedOptions.clipboardSnoopingAll || !pasteboard.typesAreSensitive {
                    Task {
                        let i = NSItemProvider(object: text as NSItemProviderWriting)
                        _ = await Model.addItems(itemProviders: [i], indexPath: IndexPath(item: 0, section: 0), overrides: nil, filterContext: keyGladysControllerIfExists?.filter)
                    }
                }
            }
            timer.tolerance = 0.5
            pasteboardObservationTimer = timer

        } else if !snoop, let p = pasteboardObservationTimer {
            p.invalidate()
            pasteboardObservationTimer = nil
        }
    }

    @IBAction private func importSelected(_: NSMenuItem) {
        guard let controller = keyGladysControllerIfExists, let w = controller.view.window else { return }

        if !w.isVisible {
            controller.showWindow(window: w)
        }

        let o = NSOpenPanel()
        o.title = "Import Archive…"
        o.prompt = "Import"
        o.message = "Select an archive from which to\nmerge items into your existing collection."
        o.isExtensionHidden = true
        o.allowedContentTypes = [.gladysArchive]
        let response = o.runModal()
        if response == .OK, let url = o.url {
            proceedWithImport(from: url)
        }
    }

    private func proceedWithImport(from url: URL) {
        startProgress(for: nil, titleOverride: "Importing items from archive, this can take a moment…")
        Task { @MainActor in // give UI a chance to update
            do {
                try ImportExport().importArchive(from: url, removingOriginal: false)
                endProgress()
            } catch {
                endProgress()
                await genericAlert(title: "Operation Failed", message: error.finalDescription)
            }
        }
    }

    @IBAction private func exportSelected(_: NSMenuItem) {
        guard let controller = keyGladysControllerIfExists, let w = controller.view.window else { return }

        if !w.isVisible {
            controller.showWindow(window: w)
        }

        let s = NSSavePanel()
        s.title = "Export Archive…"
        s.prompt = "Export"
        s.message = "Export your colection for importing\nto other devices, or as backup."
        s.isExtensionHidden = true
        s.nameFieldStringValue = "Gladys Archive"
        s.allowedContentTypes = [.gladysArchive]
        let response = s.runModal()
        if response == .OK, let selectedUrl = s.url {
            let p = ImportExport().createArchive(using: controller.filter) { result in
                self.createOperationDone(selectedUrl: selectedUrl, result: result)
            }
            startProgress(for: p)
        }
    }

    @objc private func onlyVisibleItemsToggled(_ sender: NSButton) {
        PersistedOptions.exportOnlyVisibleItems = sender.integerValue == 1
    }

    @IBAction private func zipSelected(_: NSMenuItem) {
        guard let controller = keyGladysControllerIfExists, let w = controller.view.window else { return }
        if !w.isVisible {
            controller.showWindow(window: w)
        }

        let optionView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 44))
        let selectItemsOnlyOption = NSButton(checkboxWithTitle: "Add only visible items", target: self, action: #selector(onlyVisibleItemsToggled(_:)))
        selectItemsOnlyOption.integerValue = PersistedOptions.exportOnlyVisibleItems ? 1 : 0
        selectItemsOnlyOption.frame = optionView.bounds
        optionView.addSubview(selectItemsOnlyOption)

        let s = NSSavePanel()
        s.accessoryView = optionView
        s.title = "Create ZIP…"
        s.prompt = "Create ZIP"
        s.message = "Create a ZIP file of the current collection."
        s.isExtensionHidden = true
        s.nameFieldStringValue = "Gladys"
        s.allowedContentTypes = [.zip]
        let response = s.runModal()
        if response == .OK, let selectedUrl = s.url {
            assert(Thread.isMainThread)
            let p = ImportExport().createZip(using: controller.filter) { result in
                self.createOperationDone(selectedUrl: selectedUrl, result: result)
            }
            startProgress(for: p)
        }
    }

    @objc private func showPreferences(_ sender: Any?) {
        if let prefs = NSApp.orderedWindows.first(where: { $0.contentViewController is Preferences }) {
            prefs.makeKeyAndOrderFront(sender)
            return
        }

        let controller = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "preferences") as! NSWindowController
        if let w = controller.window {
            w.makeKeyAndOrderFront(sender)
        }
    }

    @MainActor
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(aboutSelected(_:))
            || menuItem.action == #selector(newWindowSelected(_:))
            || menuItem.action == #selector(showPreferences(_:)) {
            return true
        }

        guard let controller = keyGladysControllerIfExists else { return false }

        if (menuItem.parent?.title ?? "").hasPrefix("Sort ") {
            return !controller.filter.filteredDrops.isEmpty
        }

        switch menuItem.action {
        case #selector(exportSelected(_:)), #selector(importSelected(_:)), #selector(zipSelected(_:)):
            return !isDisplayingProgress
        default:
            return true
        }
    }

    private func createOperationDone(selectedUrl: URL, result: Result<URL, Error>) {
        Task { @MainActor in
            endProgress()
        }

        switch result {
        case let .success(createdUrl):
            do {
                let fm = FileManager.default
                try fm.moveAndReplaceItem(at: createdUrl, to: selectedUrl)
                try fm.setAttributes([FileAttributeKey.extensionHidden: true], ofItemAtPath: selectedUrl.path)
                NSWorkspace.shared.activateFileViewerSelecting([selectedUrl])
            } catch {
                Task {
                    await genericAlert(title: "Operation Failed", message: error.finalDescription)
                }
            }

        case let .failure(error):
            Task {
                await genericAlert(title: "Operation Failed", message: error.finalDescription)
            }
        }
    }

    func application(_: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in
            await CloudManager.acceptShare(metadata)
        }
    }

    ////////////////////////////////////////////// Sorting

    @IBOutlet var sortAscendingMenu: NSMenu!
    @IBOutlet var sortDescendingMenu: NSMenu!

    @MainActor
    @objc private func sortOptionSelected(_ sender: NSMenu) {
        guard let controller = keyGladysControllerIfExists else { return }
        let selectedItems = ContiguousArray(controller.selectedItems)
        if selectedItems.count < 2 {
            proceedWithSort(sender: sender, items: [])
        } else {
            let a = NSAlert()
            a.messageText = "Sort selected items?"
            a.informativeText = "You have selected a range of items. Would you like to sort just the selected items, or sort all the items in your collection?"
            _ = a.addButton(withTitle: "Sort Selected")
            _ = a.addButton(withTitle: "Sort All")
            _ = a.addButton(withTitle: "Cancel")
            let response = a.runModal()
            switch response.rawValue {
            case 1000:
                proceedWithSort(sender: sender, items: selectedItems)
            case 1001:
                proceedWithSort(sender: sender, items: [])
            default:
                break
            }
        }
    }

    @MainActor
    private func proceedWithSort(sender: NSMenu, items: ContiguousArray<ArchivedItem>) {
        if let sortOption = SortOption.options.first(where: { $0.ascendingTitle == sender.title }) {
            let sortMethod = sortOption.handlerForSort(itemsToSort: items, ascending: true)
            sortMethod()
        } else if let sortOption = SortOption.options.first(where: { $0.descendingTitle == sender.title }) {
            let sortMethod = sortOption.handlerForSort(itemsToSort: items, ascending: false)
            sortMethod()
        }
    }

    /////////////////////////////////////////// Progress reports

    private var progressController: ProgressViewController?

    private func startProgress(for progress: Progress?, titleOverride: String? = nil) {
        if isDisplayingProgress {
            endProgress()
        }
        let progressWindow = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("showProgress")) as! NSWindowController
        let pvc = progressWindow.contentViewController as! ProgressViewController
        pvc.startMonitoring(progress: progress, titleOverride: titleOverride)
        progressController = pvc
        progressWindow.window?.makeKeyAndOrderFront(nil)
    }

    private var isDisplayingProgress: Bool {
        progressController != nil
    }

    @objc private func endProgress() {
        if let p = progressController {
            progressController = nil
            p.endMonitoring()
            p.view.window?.close()
        }
    }
}
