import GladysAppKit
import GladysCommon
import GladysUI
import MapKit
import SwiftUI

class FirstMouseView: NSView {
    override final func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    @IBInspectable final var bgColor: NSColor? {
        didSet {
            if oldValue != bgColor {
                layer?.setNeedsDisplay()
            }
        }
    }

    final func flatColor() {
        layer?.contents = nil
    }

    override final func updateLayer() { // explicitly not calling super, as per docs
        layer?.backgroundColor = bgColor?.cgColor
    }
}

final class FirstMouseImageView: NSImageView {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}

final class ColourView: FirstMouseView {}

extension NSMenu {
    func addItem(_ title: String, action: Selector, keyEquivalent: String, keyEquivalentModifierMask: NSEvent.ModifierFlags) {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.keyEquivalentModifierMask = keyEquivalentModifierMask
        addItem(menuItem)
    }
}

final class DropCell: NSCollectionViewItem, NSMenuDelegate {
    private var existingPreviewView: FirstMouseView?

    private var hostGladysController: ViewController {
        view.window!.gladysController!
    }

    private let myWrapper = ArchivedItemWrapper()
    private lazy var itemViewController = NSHostingController(rootView: ItemView(wrapper: myWrapper))

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        let menu = NSMenu()
        menu.delegate = self
        view.menu = menu

        view.clipsToBounds = false
        view.wantsLayer = true
        view.layer?.shouldRasterize = true

        itemViewController.view.clipsToBounds = false
        itemViewController.view.layer?.cornerRadius = cellCornerRadius
    }

    required init?(coder _: NSCoder) {
        abort()
    }

    private var lastLayout = CGSize.zero

    override func viewWillLayout() {
        let size = view.bounds.size
        if lastLayout != size {
            if itemViewController.parent == nil {
                hostGladysController.addChildController(itemViewController, to: view)
            }
            myWrapper.configure(with: archivedDropItem, size: size, style: .square)
            lastLayout = size
        }
        view.layer?.rasterizationScale = view.window?.screen?.backingScaleFactor ?? 1

        super.viewWillLayout()
    }

    override var representedObject: Any? {
        get {
            archivedDropItem
        }
        set {
            archivedDropItem = newValue as? ArchivedItem
        }
    }

    override func loadView() {
        view = NSView()
    }

    private weak var archivedDropItem: ArchivedItem? {
        didSet {
            lastLayout = .zero
            view.needsLayout = true
        }
    }

    var previewImage: NSImage? {
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        let img = NSImage(size: bounds.size)
        view.cacheDisplay(in: bounds, to: rep)
        img.addRepresentation(rep)
        return img
    }

    @objc private func infoSelected() {
        hostGladysController.info(self)
    }

    @objc private func openSelected() {
        hostGladysController.open(self)
    }

    @objc private func copySelected() {
        hostGladysController.copy(self)
    }

    @objc private func duplicateSelected() {
        hostGladysController.duplicateItem(self)
    }

    @objc private func lockSelected() {
        hostGladysController.createLock(self)
    }

    @objc private func shareSelected() {
        hostGladysController.shareSelected(self)
    }

    @objc private func topSelected() {
        hostGladysController.moveToTop(self)
    }

    @objc private func labelsSelected() {
        hostGladysController.editLabels(self)
    }

    @objc private func unlockSelected() {
        hostGladysController.unlock(self)
    }

    @objc private func removeLockSelected() {
        hostGladysController.removeLock(self)
    }

    @objc private func deleteSelected() {
        hostGladysController.delete(self)
    }

    @IBAction private func cancelSelected(_: NSButton) {
        if let archivedDropItem, archivedDropItem.status.shouldDisplayLoading {
            Model.delete(items: [archivedDropItem])
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        hostGladysController.addCellToSelection(self)

        menu.removeAllItems()
        menu.title = ""

        guard let item = archivedDropItem else {
            return
        }

        var lockItems = [NSMenuItem]()
        if hostGladysController.lockableSelectedItems.isPopulated {
            let m = NSMenuItem(title: "Lock", action: #selector(lockSelected), keyEquivalent: "")
            lockItems.append(m)
        }
        if hostGladysController.unlockableSelectedItems.isPopulated {
            let m = NSMenuItem(title: "Unlock", action: #selector(unlockSelected), keyEquivalent: "")
            lockItems.append(m)
        }
        if hostGladysController.removableLockSelectedItems.isPopulated {
            let m = NSMenuItem(title: "Remove Lock", action: #selector(removeLockSelected), keyEquivalent: "")
            lockItems.append(m)
        }

        if !item.flags.contains(.needsUnlock) {
            menu.title = item.displayTitleOrUuid
            menu.addItem("Get Info", action: #selector(infoSelected), keyEquivalent: "i", keyEquivalentModifierMask: .command)
            menu.addItem("Open", action: #selector(openSelected), keyEquivalent: "o", keyEquivalentModifierMask: .command)
            menu.addItem("Move to Top", action: #selector(topSelected), keyEquivalent: "m", keyEquivalentModifierMask: .command)
            menu.addItem("Duplicate", action: #selector(duplicateSelected), keyEquivalent: "d", keyEquivalentModifierMask: .command)
            menu.addItem("Copy", action: #selector(copySelected), keyEquivalent: "c", keyEquivalentModifierMask: .command)
            menu.addItem("Share", action: #selector(shareSelected), keyEquivalent: "s", keyEquivalentModifierMask: [.command, .option])
            menu.addItem("Labels…", action: #selector(labelsSelected), keyEquivalent: "l", keyEquivalentModifierMask: [.command, .option])

            let colourMenu = NSMenu()
            var count = 0
            for color in ItemColor.allCases {
                let entry = NSMenuItem(title: color.title, action: #selector(colorSelected), keyEquivalent: "")
                entry.tag = count
                entry.image = color.img
                entry.state = color == item.highlightColor ? .on : .off
                colourMenu.addItem(entry)
                count += 1
            }
            let colours = NSMenuItem(title: "Highlight", action: nil, keyEquivalent: "")
            colours.submenu = colourMenu
            menu.addItem(colours)
        }

        if lockItems.isPopulated {
            menu.addItem(NSMenuItem.separator())
            for item in lockItems {
                item.isEnabled = true
                menu.addItem(item)
            }
        }

        if !item.flags.contains(.needsUnlock) {
            menu.addItem(NSMenuItem.separator())
            menu.addItem("Delete", action: #selector(deleteSelected), keyEquivalent: String(format: "%c", NSBackspaceCharacter), keyEquivalentModifierMask: .command)
        }
    }

    @objc private func colorSelected(sender: NSMenuItem) {
        hostGladysController.updateColour(sender)
    }

    override var isSelected: Bool {
        didSet {
            guard let l = itemViewController.view.layer else { return }
            if isSelected {
                l.borderColor = NSColor.g_colorTint.cgColor
                l.borderWidth = 3
            } else {
                l.borderColor = .clear
                l.borderWidth = 0
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            actioned(fromTouchbar: false)
        }
    }

    func actioned(fromTouchbar: Bool) {
        let action = fromTouchbar ? PersistedOptions.actionOnTouchbar : PersistedOptions.actionOnTap
        if action == .none {
            return
        }

        if let a = archivedDropItem, a.flags.contains(.needsUnlock) {
            hostGladysController.unlock(self)
        } else {
            switch action {
            case .copy:
                copySelected()
            case .infoPanel:
                infoSelected()
            case .open:
                openSelected()
            case .preview:
                hostGladysController.toggleQuickLookPreviewPanel(nil)
            case .none:
                break
            }
        }
    }
}
