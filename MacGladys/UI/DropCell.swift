import Cocoa
import GladysCommon
import MapKit

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

final class TokenTextField: NSTextField {
    var tintColor = NSColor.g_colorTint
    private var highlightColor: NSColor { tintColor.withAlphaComponent(0.7) }

    private static let highlightTextKey = NSAttributedString.Key("HighlightText")
    private static let separator = "   "
    private static let separatorCount = separator.utf16.count

    var labels: [String]? {
        didSet {
            guard let labels, !labels.isEmpty, let font else {
                attributedStringValue = NSAttributedString()
                return
            }

            let p = NSMutableParagraphStyle()
            p.alignment = alignment
            p.lineBreakMode = .byWordWrapping
            p.lineSpacing = 3

            let ls = labels.map { $0.replacingOccurrences(of: " ", with: "\u{a0}") }
            let joinedLabels = ls.joined(separator: TokenTextField.separator)
            let string = NSMutableAttributedString(string: joinedLabels, attributes: [
                .font: font,
                .foregroundColor: tintColor,
                .paragraphStyle: p
            ])

            var start = 0
            for label in ls {
                let len = label.utf16.count
                string.addAttribute(TokenTextField.highlightTextKey, value: 1, range: NSRange(location: start, length: len))
                start += len + TokenTextField.separatorCount
            }
            attributedStringValue = string
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !attributedStringValue.string.isEmpty, let labels, let context = NSGraphicsContext.current?.cgContext else { return }

        let insideRect = dirtyRect.insetBy(dx: 1, dy: 0).offsetBy(dx: -1, dy: 0)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedStringValue)
        let path = CGPath(rect: insideRect, transform: nil)
        let totalFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)

        context.translateBy(x: 0, y: insideRect.size.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(totalFrame, context)

        if labels.isEmpty {
            return
        }

        context.setStrokeColor(highlightColor.cgColor)
        context.setLineWidth(0.5)

        let lines = CTFrameGetLines(totalFrame) as NSArray
        let lineCount = lines.count

        var origins = [CGPoint](repeating: .zero, count: lineCount)
        CTFrameGetLineOrigins(totalFrame, CFRangeMake(0, 0), &origins)

        for index in 0 ..< lineCount {
            let line = lines[index] as! CTLine
            let lineFrame = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
            let lineStart = (insideRect.width - lineFrame.width) * 0.5

            for r in CTLineGetGlyphRuns(line) as NSArray {
                let run = r as! CTRun
                let attributes = CTRunGetAttributes(run) as NSDictionary

                if attributes["HighlightText"] != nil {
                    var runBounds = lineFrame

                    runBounds.size.width = CGFloat(CTRunGetImageBounds(run, context, CFRangeMake(0, 0)).width) + 8
                    runBounds.origin.x = lineStart + CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, nil) - 4
                    runBounds.origin.y = origins[index].y - 2.5
                    runBounds = runBounds.insetBy(dx: 1, dy: 0)
                    runBounds.origin.x += 0.5
                    runBounds.size.height += 0.5

                    context.addPath(CGPath(roundedRect: runBounds, cornerWidth: 3, cornerHeight: 3, transform: nil))
                }
            }
        }

        context.strokePath()
    }
}

final class MiniMapView: FirstMouseView {
    private var snapshotOptions = Images.SnapshotOptions(coordinate: kCLLocationCoordinate2DInvalid, range: 200, outputSize: CGSize(width: 512, height: 512))

    func show(location: MKMapItem) {
        let newCoordinate = location.placemark.coordinate
        if snapshotOptions.coordinate == newCoordinate { return }
        snapshotOptions.coordinate = newCoordinate

        let cacheKey = "\(newCoordinate.latitude) \(newCoordinate.longitude)"
        if let existingImage = Images.shared[cacheKey] {
            layer?.contents = existingImage
            return
        }

        layer?.contents = nil

        Task {
            if let snapshot = try? await Images.shared.mapSnapshot(with: snapshotOptions) {
                Images.shared[cacheKey] = snapshot
                layer?.contents = snapshot
            }
        }
    }

    init(at location: MKMapItem) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        show(location: location)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    @IBOutlet private var topLabel: NSTextField!
    @IBOutlet private var bottomLabel: NSTextField!
    @IBOutlet private var image: FirstMouseView!
    @IBOutlet private var progressView: NSProgressIndicator!
    @IBOutlet private var cancelButton: NSButton!
    @IBOutlet private var lockImage: NSImageView!
    @IBOutlet private var labelTokenField: TokenTextField!
    @IBOutlet private var sharedIcon: NSImageView!
    @IBOutlet private var bottomStackView: NSStackView!
    @IBOutlet private var copiedLabel: NSTextField!

    private var existingPreviewView: FirstMouseView?

    private var hostGladysController: ViewController {
        view.window!.gladysController!
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        image.layer?.cornerRadius = 5

        view.layer?.cornerRadius = 10

        view.menu = NSMenu()
        view.menu?.delegate = self

        isSelected = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(itemModified(_:)), name: .ItemModified, object: nil)
        n.addObserver(self, selector: #selector(itemModified(_:)), name: .IngestComplete, object: nil)

        if archivedDropItem != nil {
            reDecorate()
        }
    }

    @objc private func itemModified(_ notification: Notification) {
        if let item = notification.object as? ArchivedItem, item == archivedDropItem {
            archivedDropItem = item
        }
    }

    override var representedObject: Any? {
        get {
            archivedDropItem
        }
        set {
            archivedDropItem = newValue as? ArchivedItem
        }
    }

    private weak var archivedDropItem: ArchivedItem? {
        didSet {
            if isViewLoaded {
                reDecorate()
            }
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

    override func prepareForReuse() {
        super.prepareForReuse()
        image.flatColor()
    }

    private func setHighlightColor(_ highlightColor: ItemColor, highlightBottomLabel: Bool) {
        (view as? FirstMouseView)?.bgColor = highlightColor.color
        if highlightColor == .none {
            topLabel.textColor = .g_colorComponentLabel
            bottomLabel.textColor = highlightBottomLabel ? .g_colorTint : .g_colorComponentLabel
            labelTokenField.tintColor = .g_colorTint
        } else if highlightColor.invertText {
            topLabel.textColor = .g_colorComponentLabelInverse
            bottomLabel.textColor = .g_colorComponentLabelInverse
            labelTokenField.tintColor = .g_colorComponentLabelInverse
        } else {
            topLabel.textColor = .g_colorComponentLabel
            bottomLabel.textColor = .g_colorComponentLabel
            labelTokenField.tintColor = .g_colorComponentLabel
        }
    }

    private func reDecorate() {
        let item = archivedDropItem

        var wantColourView = false
        var wantMapView = false
        var hideCancel = true
        var hideSpinner = true
        var hideImage = true
        var hideLock = true
        var hideLabels = true
        var share = ArchivedItem.ShareMode.none

        var topLabelText = ""
        var topLabelAlignment = NSTextAlignment.center

        var bottomLabelText = ""
        var bottomLabelAlignment = NSTextAlignment.center

        image.flatColor()

        if let item {
            if item.shouldDisplayLoading {
                progressView.startAnimation(nil)
                hideCancel = item.needsReIngest
                hideSpinner = false
                setHighlightColor(.none, highlightBottomLabel: false)

            } else if item.flags.contains(.needsUnlock) {
                progressView.stopAnimation(nil)
                hideLock = false
                bottomLabelAlignment = .center
                bottomLabelText = item.lockHint ?? ""
                share = item.shareMode
                setHighlightColor(.none, highlightBottomLabel: false)

            } else {
                progressView.stopAnimation(nil)
                var bottomLabelHighlight = false
                hideImage = false
                share = item.shareMode
                let cacheKey = item.imageCacheKey
                if let cachedImage = Images.shared[cacheKey] {
                    image.layer?.contents = cachedImage
                } else {
                    let u1 = item.uuid
                    Task.detached {
                        let img = item.displayIcon
                        let final = img.isTemplate ? img.template(with: NSColor.g_colorTint) : img
                        Images.shared[cacheKey] = final
                        await MainActor.run { [weak self] in
                            if let self, let latestItemUuid = self.archivedDropItem?.uuid, u1 == latestItemUuid {
                                self.image.layer?.contents = final
                                self.image.updateLayer()
                            }
                        }
                    }
                }

                let primaryLabel: NSTextField
                let secondaryLabel: NSTextField

                let titleInfo = item.displayText
                topLabelAlignment = titleInfo.1
                topLabelText = titleInfo.0 ?? ""

                if PersistedOptions.displayNotesInMainView, !item.note.isEmpty {
                    bottomLabelText = item.note
                    bottomLabelHighlight = true
                } else if let url = item.associatedWebURL {
                    bottomLabelText = url.absoluteString
                    if topLabelText == bottomLabelText {
                        topLabelText = ""
                    }
                }

                if PersistedOptions.displayLabelsInMainView, !item.labels.isEmpty {
                    hideLabels = false
                }

                if bottomLabelText.isEmpty, !topLabelText.isEmpty {
                    bottomLabelText = topLabelText
                    bottomLabelAlignment = topLabelAlignment
                    topLabelText = ""

                    primaryLabel = bottomLabel
                    secondaryLabel = topLabel
                } else {
                    primaryLabel = topLabel
                    secondaryLabel = bottomLabel
                }

                switch item.displayMode {
                case .center:
                    image.layer?.contentsGravity = .center
                    primaryLabel.maximumNumberOfLines = 6
                    secondaryLabel.maximumNumberOfLines = 2
                case .fill:
                    image.layer?.contentsGravity = .resizeAspectFill
                    primaryLabel.maximumNumberOfLines = 6
                    secondaryLabel.maximumNumberOfLines = 2
                case .fit:
                    image.layer?.contentsGravity = .resizeAspect
                    primaryLabel.maximumNumberOfLines = 6
                    secondaryLabel.maximumNumberOfLines = 2
                case .circle:
                    image.layer?.contentsGravity = .resizeAspectFill
                    primaryLabel.maximumNumberOfLines = 6
                    secondaryLabel.maximumNumberOfLines = 2
                }

                // if we're showing an icon, let's try to enhance things a bit
                if image.layer?.contentsGravity == .center, let backgroundItem = item.backgroundInfoObject {
                    if let mapItem = backgroundItem as? MKMapItem {
                        wantMapView = true
                        if let m = existingPreviewView as? MiniMapView {
                            m.show(location: mapItem)
                        } else {
                            if let m = existingPreviewView {
                                m.removeFromSuperview()
                            }
                            let m = MiniMapView(at: mapItem)
                            m.translatesAutoresizingMaskIntoConstraints = false
                            image.addSubview(m)
                            NSLayoutConstraint.activate([
                                m.leadingAnchor.constraint(equalTo: image.leadingAnchor),
                                m.trailingAnchor.constraint(equalTo: image.trailingAnchor),
                                m.topAnchor.constraint(equalTo: image.topAnchor),
                                m.bottomAnchor.constraint(equalTo: image.bottomAnchor)
                            ])

                            existingPreviewView = m
                        }
                    } else if let colourItem = backgroundItem as? NSColor {
                        wantColourView = true
                        if let m = existingPreviewView as? ColourView {
                            m.layer?.backgroundColor = colourItem.cgColor
                        } else {
                            if let m = existingPreviewView {
                                m.removeFromSuperview()
                            }
                            let m = ColourView()
                            m.wantsLayer = true
                            m.layer?.backgroundColor = colourItem.cgColor
                            m.translatesAutoresizingMaskIntoConstraints = false
                            image.addSubview(m)
                            NSLayoutConstraint.activate([
                                m.leadingAnchor.constraint(equalTo: image.leadingAnchor),
                                m.trailingAnchor.constraint(equalTo: image.trailingAnchor),
                                m.topAnchor.constraint(equalTo: image.topAnchor),
                                m.bottomAnchor.constraint(equalTo: image.bottomAnchor)
                            ])

                            existingPreviewView = m
                        }
                    }
                }
                setHighlightColor(item.highlightColor, highlightBottomLabel: bottomLabelHighlight)
            }

        } else { // item is nil
            progressView.stopAnimation(nil)
            setHighlightColor(.none, highlightBottomLabel: false)
        }

        if !(wantMapView || wantColourView), let e = existingPreviewView {
            e.removeFromSuperview()
            existingPreviewView = nil
        }

        labelTokenField.isHidden = hideLabels
        labelTokenField.labels = item?.labels

        topLabel.stringValue = topLabelText
        topLabel.isHidden = topLabelText.isEmpty
        topLabel.alignment = topLabelAlignment

        let hideBottomLabel = bottomLabelText.isEmpty
        bottomLabel.stringValue = bottomLabelText
        bottomLabel.isHidden = hideBottomLabel
        bottomLabel.alignment = bottomLabelAlignment

        image.isHidden = hideImage
        cancelButton.isHidden = hideCancel
        progressView.isHidden = hideSpinner
        lockImage.isHidden = hideLock

        switch share {
        case .none:
            sharedIcon.isHidden = true
            bottomStackView.isHidden = hideBottomLabel
        case .elsewhereReadOnly, .elsewhereReadWrite:
            sharedIcon.contentTintColor = NSColor.systemGray
            sharedIcon.isHidden = false
            bottomStackView.isHidden = false
        case .sharing:
            sharedIcon.contentTintColor = NSColor.g_colorTint
            sharedIcon.isHidden = false
            bottomStackView.isHidden = false
        }
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
        if let archivedDropItem, archivedDropItem.shouldDisplayLoading {
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
        if !hostGladysController.lockableSelectedItems.isEmpty {
            let m = NSMenuItem(title: "Lock", action: #selector(lockSelected), keyEquivalent: "")
            lockItems.append(m)
        }
        if !hostGladysController.unlockableSelectedItems.isEmpty {
            let m = NSMenuItem(title: "Unlock", action: #selector(unlockSelected), keyEquivalent: "")
            lockItems.append(m)
        }
        if !hostGladysController.removableLockSelectedItems.isEmpty {
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

        if !lockItems.isEmpty {
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
            guard let l = view.layer else { return }
            if isSelected {
                l.borderColor = NSColor.g_colorTint.cgColor
                l.borderWidth = 3
            } else {
                l.borderColor = NSColor.labelColor.withAlphaComponent(0.2).cgColor
                l.borderWidth = 1.0 / (NSScreen.main?.backingScaleFactor ?? 1)
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
                copiedLabel.animator().isHidden = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1000 * NSEC_PER_MSEC)
                    copiedLabel.animator().isHidden = true
                }
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
