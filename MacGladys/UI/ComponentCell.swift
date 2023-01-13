import Cocoa

protocol ComponentCellDelegate: AnyObject {
    func componentCell(_ componentCell: ComponentCell, wants action: ComponentCell.Action)
}

final class ComponentCell: NSCollectionViewItem, NSMenuDelegate {
    enum Action {
        case open, copy, delete, archivePage, archiveThumbnail, share, edit, focus, reveal
    }

    @IBOutlet private var descriptionLabel: NSTextField!
    @IBOutlet private var previewLabel: NSTextField!
    @IBOutlet private var sizeLabel: NSTextField!
    @IBOutlet private var centreBlock: FirstMouseView!
    @IBOutlet private var spinner: NSProgressIndicator!

    weak var delegate: ComponentCellDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer?.cornerRadius = 8
    }

    override var representedObject: Any? {
        didSet {
            view.menu = shortcutMenu
            view.needsLayout = true
        }
    }

    var animateArchiving = false {
        didSet {
            view.needsLayout = true
        }
    }

    override func viewWillLayout() {
        super.viewWillLayout()
        decorate()
    }

    private var shortcutMenu: NSMenu? {
        guard let item = representedObject as? Component else { return nil }
        let m = NSMenu(title: item.displayTitle ?? "")
        m.addItem("Open", action: #selector(openSelected), keyEquivalent: "o", keyEquivalentModifierMask: .command)
        m.addItem("Copy", action: #selector(copySelected), keyEquivalent: "c", keyEquivalentModifierMask: .command)
        m.addItem("Share", action: #selector(shareSelected), keyEquivalent: "s", keyEquivalentModifierMask: [.command, .option])
        m.addItem("Reveal in Finder", action: #selector(revealSelected), keyEquivalent: "r", keyEquivalentModifierMask: [.command, .option])
        if let parent = Model.item(uuid: item.parentUuid), parent.shareMode != .elsewhereReadOnly {
            if item.isArchivable {
                m.addItem("Edit", action: #selector(editSelected), keyEquivalent: "e", keyEquivalentModifierMask: [.command, .option])

                let archiveSubMenu = NSMenu()
                archiveSubMenu.addItem("Archive Target", action: #selector(archivePageSelected), keyEquivalent: "", keyEquivalentModifierMask: [])
                archiveSubMenu.addItem("Image Thumbnail", action: #selector(archiveThumbnailSelected), keyEquivalent: "", keyEquivalentModifierMask: [])

                let archiveMenu = NSMenuItem(title: "Download…", action: nil, keyEquivalent: "")
                archiveMenu.submenu = archiveSubMenu
                m.addItem(archiveMenu)
            }
            m.addItem(NSMenuItem.separator())
            m.addItem("Delete", action: #selector(deleteSelected), keyEquivalent: String(format: "%c", NSBackspaceCharacter), keyEquivalentModifierMask: .command)
        }
        m.delegate = self
        return m
    }

    func menuWillOpen(_: NSMenu) {
        delegate?.componentCell(self, wants: .focus)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            openSelected()
        }
    }

    @objc private func openSelected() {
        delegate?.componentCell(self, wants: .open)
    }

    @objc private func copySelected() {
        delegate?.componentCell(self, wants: .copy)
    }

    @objc private func shareSelected() {
        delegate?.componentCell(self, wants: .share)
    }

    @objc private func revealSelected() {
        delegate?.componentCell(self, wants: .reveal)
    }

    @objc private func deleteSelected() {
        delegate?.componentCell(self, wants: .delete)
    }

    @objc private func archivePageSelected() {
        delegate?.componentCell(self, wants: .archivePage)
    }

    @objc private func archiveThumbnailSelected() {
        delegate?.componentCell(self, wants: .archiveThumbnail)
    }

    @objc private func editSelected() {
        delegate?.componentCell(self, wants: .edit)
    }

    private func decorate() {
        guard let typeEntry = representedObject as? Component else { return }

        sizeLabel.stringValue = typeEntry.sizeDescription ?? ""
        descriptionLabel.stringValue = "\(typeEntry.typeDescription.uppercased()) (\(typeEntry.typeIdentifier.uppercased()))"
        if animateArchiving {
            spinner.startAnimation(nil)
            previewLabel.isHidden = true
            return
        } else {
            spinner.stopAnimation(nil)
            previewLabel.isHidden = false
        }

        var showPreview = false
        if let title = typeEntry.displayTitle ?? typeEntry.accessoryTitle ?? typeEntry.encodedUrl?.path {
            previewLabel.alphaValue = 1.0
            previewLabel.stringValue = "\"\(title)\""
            previewLabel.alignment = typeEntry.displayTitleAlignment
        } else if typeEntry.dataExists {
            previewLabel.alphaValue = 0.7
            if typeEntry.isWebArchive {
                previewLabel.stringValue = ComponentCell.shortFormatter.string(from: typeEntry.createdAt)
            } else if typeEntry.displayIconContentMode == .fill {
                previewLabel.stringValue = ""
                showPreview = true
            } else {
                previewLabel.stringValue = "Binary Data"
            }
            previewLabel.alignment = .center
        } else {
            previewLabel.alphaValue = 0.7
            previewLabel.stringValue = "Loading Error"
            previewLabel.alignment = .center
        }

        if showPreview, let icon = typeEntry.componentIcon {
            Task {
                centreBlock.layer?.contents = await icon.desaturated()
            }
        } else {
            centreBlock.layer?.contents = nil
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        centreBlock.layer?.contentsGravity = .resizeAspectFill
        centreBlock.layer?.cornerRadius = 4
    }

    private static let shortFormatter: DateFormatter = {
        let d = DateFormatter()
        d.doesRelativeDateFormatting = true
        d.dateStyle = .short
        d.timeStyle = .short
        return d
    }()

    override var isSelected: Bool {
        didSet {
            guard let l = view.layer else { return }
            if isSelected {
                l.borderColor = NSColor.g_colorTint.cgColor
                l.borderWidth = 2
            } else {
                l.borderColor = NSColor.clear.cgColor
                l.borderWidth = 0
            }
        }
    }
}
