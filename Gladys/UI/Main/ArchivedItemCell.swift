import CloudKit
import GladysCommon
import MapKit
import UIKit
import GladysUI

#if canImport(PencilKit)
    import PencilKit
#endif

final class ArchivedItemCell: UICollectionViewCell {
    @IBOutlet private var image: GladysImageView!
    @IBOutlet private var bottomLabel: UILabel!
    @IBOutlet private var labelsLabel: HighlightLabel!
    @IBOutlet private var labelsHolder: UIView!

    @IBOutlet private var container: UIView!

    @IBOutlet private var topLabel: UILabel!
    @IBOutlet private var topLabelHolder: UIView!

    @IBOutlet private var progressView: UIProgressView!
    @IBOutlet private var progressViewHolder: UIView!

    @IBOutlet private var cancelButton: UIButton!
    @IBOutlet private var lockImage: UIImageView!
    @IBOutlet private var spinner: UIActivityIndicatorView!

    @IBOutlet private var topLabelLeft: NSLayoutConstraint!
    @IBOutlet private var labelStack: UIStackView!

    private var tickImage: UIImageView?
    private var tickHolder: UIView?
    private var shareImage: UIImageView?
    private var shareHolder: UIView?

    var dragParameters: UIDragPreviewParameters {
        let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 8, height: 8))
        let params = UIDragPreviewParameters()
        params.visiblePath = path
        return params
    }

    @IBAction private func cancelSelected(_: UIButton) {
        progressView.observedProgress = nil
        if let archivedDropItem, archivedDropItem.shouldDisplayLoading {
            Model.delete(items: [archivedDropItem])
        }
    }

    private var shareColor: UIColor? {
        if archivedDropItem?.shareMode == .sharing {
            return UIColor.g_colorTint
        } else {
            return UIColor.secondaryLabel
        }
    }

    override func tintColorDidChange() {
        let c = tintColor
        tickImage?.tintColor = c
        shareImage?.tintColor = shareColor
        cancelButton?.tintColor = c
        lockImage.tintColor = c
        topLabel.highlightedTextColor = c
        bottomLabel.highlightedTextColor = c
        labelsLabel.tintColor = c
        image.tintColor = .g_colorTint
    }

    override var isSelected: Bool {
        didSet {
            tickImage?.isHighlighted = isSelected
        }
    }

    override var isHighlighted: Bool {
        get { false }
        set {}
    }

    var isEditing = false {
        didSet {
            if isEditing, tickHolder == nil, progressViewHolder.isHidden {
                let img = UIImageView(frame: .zero)
                img.translatesAutoresizingMaskIntoConstraints = false
                img.tintColor = tintColor
                img.preferredSymbolConfiguration = UIImage.SymbolConfiguration(scale: .large)
                img.image = UIImage(systemName: "circle")
                img.highlightedImage = UIImage(systemName: "checkmark.circle.fill")
                img.isHighlighted = isSelected

                let holder = UIView(frame: .zero)
                holder.translatesAutoresizingMaskIntoConstraints = false
                holder.backgroundColor = container.backgroundColor
                holder.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMinYCorner]
                holder.layer.cornerRadius = 20
                holder.addSubview(img)
                container.addSubview(holder)

                NSLayoutConstraint.activate([
                    holder.topAnchor.constraint(equalTo: topAnchor),
                    holder.trailingAnchor.constraint(equalTo: trailingAnchor),

                    holder.widthAnchor.constraint(equalToConstant: 41),
                    holder.heightAnchor.constraint(equalToConstant: 41),

                    img.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
                    img.centerYAnchor.constraint(equalTo: holder.centerYAnchor)
                ])

                tickImage = img
                tickHolder = holder

            } else if !isEditing, let h = tickHolder {
                h.removeFromSuperview()
                tickImage = nil
                tickHolder = nil
            }
        }
    }

    var shareMode: ArchivedItem.ShareMode = .none {
        didSet {
            if oldValue == shareMode { return }
            let shouldShow = shareMode != .none
            if shouldShow, shareHolder == nil {
                let img = UIImageView(frame: .zero)
                img.translatesAutoresizingMaskIntoConstraints = false
                img.tintColor = tintColor
                img.preferredSymbolConfiguration = UIImage.SymbolConfiguration(scale: .large)
                img.image = UIImage(systemName: "person.crop.circle.fill.badge.checkmark")

                let holder = UIView(frame: .zero)
                holder.translatesAutoresizingMaskIntoConstraints = false
                holder.backgroundColor = container.backgroundColor
                holder.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMaxYCorner]
                holder.layer.cornerRadius = 20
                holder.addSubview(img)
                container.addSubview(holder)

                NSLayoutConstraint.activate([
                    holder.topAnchor.constraint(equalTo: topAnchor),
                    holder.leadingAnchor.constraint(equalTo: leadingAnchor),

                    holder.widthAnchor.constraint(equalToConstant: 41),
                    holder.heightAnchor.constraint(equalToConstant: 41),

                    img.centerXAnchor.constraint(equalTo: holder.centerXAnchor, constant: -3),
                    img.centerYAnchor.constraint(equalTo: holder.centerYAnchor)
                ])

                shareImage = img
                shareHolder = holder

            } else if !shouldShow, let h = shareHolder {
                h.removeFromSuperview()
                shareImage = nil
                shareHolder = nil
            }

            shareImage?.tintColor = shareColor
        }
    }

    var wideCell = false

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        container.layer.borderColor = UIColor.opaqueSeparator.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        focusEffect = UIFocusHaloEffect(roundedRect: bounds.insetBy(dx: 2, dy: 2), cornerRadius: 10, curve: .continuous)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        container.layer.cornerRadius = 10
        container.layer.borderWidth = 1.0 / screenScale
        container.layer.borderColor = UIColor.opaqueSeparator.cgColor

        image.accessibilityIgnoresInvertColors = true

        labelStack.setCustomSpacing(4, after: labelsHolder)

        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(itemModified(_:)), name: .ItemModified, object: nil)
        n.addObserver(self, selector: #selector(itemModified(_:)), name: .IngestComplete, object: nil)

        #if canImport(PencilKit)
            let pencil = UIIndirectScribbleInteraction(delegate: self)
            addInteraction(pencil)
        #endif

        tintColorDidChange()
    }

    weak var archivedDropItem: ArchivedItem? {
        didSet {
            reDecorate()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        progressView.observedProgress = nil
        progressView.progress = 0
        image.image = nil
    }

    deinit {
        progressView.observedProgress = nil
    }

    private var existingPreviewView: UIView?

    var lowMemoryMode = false {
        didSet {
            if lowMemoryMode != oldValue {
                reDecorate()
            }
        }
    }

    @objc private func itemModified(_ notification: Notification) {
        if (notification.object as? ArchivedItem) == archivedDropItem {
            reDecorate()
        }
    }

    private func reDecorate() {
        if lowMemoryMode {
            decorate(with: nil)
        } else {
            decorate(with: archivedDropItem)
        }
    }

    private var isFirstImport: Bool {
        guard let item = archivedDropItem else { return false }
        return item.shouldDisplayLoading && !(item.needsReIngest || item.flags.contains(.isBeingCreatedBySync))
    }

    private var highlightColor = ItemColor.none {
        didSet {
            container.backgroundColor = highlightColor.color
            if highlightColor == .none {
                topLabel.textColor = .g_colorComponentLabel
                bottomLabel.textColor = .g_colorComponentLabel
                tintColor = .g_colorTint
            } else if highlightColor.invertText {
                topLabel.textColor = .g_colorComponentLabelInverse
                bottomLabel.textColor = .g_colorComponentLabelInverse
                tintColor = .g_colorComponentLabelInverse
            } else {
                topLabel.textColor = .g_colorComponentLabel
                bottomLabel.textColor = .g_colorComponentLabel
                tintColor = .g_colorComponentLabel
            }
        }
    }

    private func decorate(with item: ArchivedItem?) {
        var wantColourView = false
        var wantMapView = false
        var hideImage = true
        var hideProgress = true
        var hideSpinner = true
        var hideLock = true
        var shared = ArchivedItem.ShareMode.none

        var topLabelText: String?
        var topLabelAlignment: NSTextAlignment?

        var bottomLabelText: String?
        var bottomLabelHighlight = false
        var bottomLabelAlignment: NSTextAlignment?
        var labels: [String]?

        progressView.observedProgress = nil
        image.wideMode = wideCell

        if let item {
            if item.shouldDisplayLoading {
                highlightColor = .none
                if isFirstImport {
                    hideProgress = false
                    progressView.observedProgress = item.loadingProgress
                } else {
                    hideSpinner = false
                }

            } else if item.flags.contains(.needsUnlock) {
                highlightColor = .none
                hideLock = false
                bottomLabelAlignment = .center
                bottomLabelText = item.lockHint
                shared = item.shareMode

            } else {
                highlightColor = item.highlightColor
                hideImage = false
                shared = item.shareMode

                let cacheKey = item.imageCacheKey
                if let cachedImage = Images.shared[cacheKey] {
                    image.image = cachedImage
                } else {
                    let u1 = item.uuid
                    Task.detached {
                        let img = item.displayIcon.preparingForDisplay()
                        Images.shared[cacheKey] = img
                        Task { @MainActor [weak self] in
                            if let self, let i = self.archivedDropItem, u1 == i.uuid {
                                self.image.image = img
                            }
                        }
                    }
                }

                let primaryLabel: UILabel
                let secondaryLabel: UILabel

                let titleInfo = item.displayText
                topLabelAlignment = titleInfo.1
                topLabelText = titleInfo.0

                if PersistedOptions.displayNotesInMainView, !item.note.isEmpty {
                    bottomLabelText = item.note
                    bottomLabelHighlight = true
                } else if let url = item.associatedWebURL {
                    bottomLabelText = url.absoluteString
                    if topLabelText == bottomLabelText {
                        topLabelText = nil
                    }
                }

                let side = window?.windowScene?.session.userInfo?["ItemSize"] as? CGFloat ?? 200
                let wideMode = side > 145
                let smallMode = side < 240

                if PersistedOptions.displayLabelsInMainView {
                    labels = item.labels
                }

                if bottomLabelText == nil, topLabelText != nil {
                    bottomLabelText = topLabelText
                    bottomLabelAlignment = topLabelAlignment
                    topLabelText = nil

                    primaryLabel = bottomLabel
                    secondaryLabel = topLabel
                } else {
                    primaryLabel = topLabel
                    secondaryLabel = bottomLabel
                }

                if wideCell {
                    primaryLabel.numberOfLines = 3
                    image.circle = false
                    switch item.displayMode {
                    case .center:
                        image.contentMode = .center
                    case .fill:
                        image.contentMode = .scaleAspectFill
                    case .fit:
                        image.contentMode = .scaleAspectFit
                    case .circle:
                        image.contentMode = .scaleAspectFill
                    }

                } else {
                    let baseLines = smallMode ? 2 : 6
                    switch item.displayMode {
                    case .center:
                        image.contentMode = .center
                        image.circle = false
                        primaryLabel.numberOfLines = wideMode ? baseLines + 2 : 2
                    case .fill:
                        image.contentMode = .scaleAspectFill
                        image.circle = false
                        primaryLabel.numberOfLines = baseLines
                    case .fit:
                        image.contentMode = .scaleAspectFit
                        image.circle = false
                        primaryLabel.numberOfLines = baseLines
                    case .circle:
                        image.contentMode = .scaleAspectFill
                        image.circle = true
                        primaryLabel.numberOfLines = baseLines
                    }
                }
                secondaryLabel.numberOfLines = 2

                // if we're showing an icon, let's try to enhance things a bit
                if image.contentMode == .center, let backgroundItem = item.backgroundInfoObject {
                    if let mapItem = backgroundItem as? MKMapItem {
                        wantMapView = true
                        if let m = existingPreviewView as? MiniMapView {
                            m.show(location: mapItem)
                        } else {
                            if let e = existingPreviewView {
                                e.removeFromSuperview()
                            }
                            let m = MiniMapView(at: mapItem)
                            image.cover(with: m)
                            existingPreviewView = m
                        }

                    } else if let color = backgroundItem as? UIColor {
                        wantColourView = true
                        if let c = existingPreviewView as? ColourView {
                            c.backgroundColor = color
                        } else {
                            if let e = existingPreviewView {
                                e.removeFromSuperview()
                            }
                            let c = ColourView()
                            c.backgroundColor = color
                            image.cover(with: c)
                            existingPreviewView = c
                        }
                    }
                }
            }

        } else { // item is nil
            image.image = nil
        }

        if !(wantColourView || wantMapView), let e = existingPreviewView {
            e.removeFromSuperview()
            existingPreviewView = nil
        }

        progressViewHolder.isHidden = hideProgress

        topLabel.text = topLabelText
        topLabelHolder.isHidden = topLabelText?.isEmpty ?? true

        bottomLabel.text = bottomLabelText
        bottomLabel.isHighlighted = bottomLabelHighlight
        bottomLabel.isHidden = bottomLabelText?.isEmpty ?? true

        if wideCell {
            topLabel.textAlignment = .natural
            bottomLabel.textAlignment = .natural
        } else {
            topLabel.textAlignment = topLabelAlignment ?? .center
            bottomLabel.textAlignment = bottomLabelAlignment ?? .center
        }

        let newLabels = labels ?? []
        labelsLabel.labels = newLabels
        labelsHolder.isHidden = newLabels.isEmpty

        image.alpha = hideImage ? 0 : 1
        lockImage.isHidden = hideLock
        shareMode = shared

        let isSpinning = spinner.isAnimating
        if isSpinning, hideSpinner {
            spinner.stopAnimating()
        } else if !isSpinning, !hideSpinner {
            spinner.startAnimating()
        }

        topLabelLeft.constant = (shareHolder == nil || wideCell) ? 0 : 41
    }

    func flash() {
        let originalColor = container.backgroundColor
        let topColor = topLabel.textColor
        let bottomColor = bottomLabel.textColor
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
            self.container.backgroundColor = UIColor.g_colorTint
            self.topLabel.textColor = .systemBackground
            self.bottomLabel.textColor = .systemBackground
        }, completion: { _ in
            UIView.animate(withDuration: 0.6, delay: 0, options: .curveEaseIn, animations: {
                self.container.backgroundColor = originalColor
            }, completion: { _ in
                self.topLabel.textColor = topColor
                self.bottomLabel.textColor = bottomColor
            })
        })
    }

    // MARK: - Menu

    override func accessibilityActivate() -> Bool {
        if progressViewHolder.isHidden {
            return super.accessibilityActivate()
        } else {
            if isFirstImport {
                cancelSelected(cancelButton)
            }
            return true
        }
    }

    override var isAccessibilityElement: Bool {
        get {
            true
        }
        set {}
    }

    override var accessibilityLabel: String? {
        get {
            if shouldDisplayLoading {
                if isFirstImport {
                    return "Importing item. Activate to cancel."
                } else {
                    return "Processing item."
                }
            }
            return (topLabel.text ?? "") + ((archivedDropItem?.isLocked ?? false) ? "\nItem Locked" : "")
        }
        set {}
    }

    override var accessibilityValue: String? {
        get {
            if shouldDisplayLoading {
                return nil

            } else {
                var bottomText = ""
                if PersistedOptions.displayLabelsInMainView, let l = archivedDropItem?.labels, !l.isEmpty {
                    bottomText.append(l.joined(separator: ", "))
                }
                if let l = bottomLabel.text {
                    if !bottomText.isEmpty {
                        bottomText.append("\n")
                    }
                    bottomText.append(l)
                }
                return [archivedDropItem?.dominantTypeDescription, image.accessibilityLabel, image.accessibilityValue, bottomText].compactMap { $0 }.joined(separator: "\n")
            }
        }
        set {}
    }

    private var shouldDisplayLoading: Bool {
        archivedDropItem?.loadingProgress != nil
    }

    var targetedPreviewItem: UITargetedPreview {
        UITargetedPreview(view: container)
    }

    #if canImport(PencilKit)
        private var notesTextView: UITextView?
    #endif
}

#if canImport(PencilKit)
    extension ArchivedItemCell: UIIndirectScribbleInteractionDelegate {
        func indirectScribbleInteraction(_: UIInteraction, shouldDelayFocusForElement _: String) -> Bool {
            false
        }

        func indirectScribbleInteraction(_: UIInteraction, willBeginWritingInElement _: String) {}

        func indirectScribbleInteraction(_: UIInteraction, didFinishWritingInElement _: String) {
            if let item = archivedDropItem, let text = notesTextView?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, item.note != text {
                item.note = text
                item.markUpdated()
                Model.save()
            }

            if let n = notesTextView {
                notesTextView = nil
                UIView.animate(withDuration: 0.15, animations: {
                    n.alpha = 0
                }, completion: { _ in
                    n.removeFromSuperview()
                })
            }
        }

        func indirectScribbleInteraction(_: UIInteraction, focusElementIfNeeded _: String, referencePoint _: CGPoint, completion: @escaping ((UIResponder & UITextInput)?) -> Void) {
            if let n = notesTextView {
                completion(n)
                return
            }

            let f = UITextView()
            f.contentInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
            f.backgroundColor = UIColor.g_colorTint
            f.tintColor = UIColor.g_colorTint
            f.textColor = .white
            f.font = UIFont.preferredFont(forTextStyle: .headline)
            f.isEditable = false
            f.isSelectable = false
            f.clipsToBounds = true
            f.layer.cornerRadius = 10
            f.layer.borderWidth = 1.0 / screenScale
            f.layer.borderColor = UIColor.opaqueSeparator.cgColor
            f.autocorrectionType = .no
            f.alpha = 0
            cover(with: f)
            notesTextView = f
            UIView.animate(withDuration: 0.15, animations: {
                f.alpha = 1
            }, completion: { _ in
                completion(f)
            })
        }

        func indirectScribbleInteraction(_: UIInteraction, requestElementsIn _: CGRect, completion: @escaping ([String]) -> Void) {
            if archivedDropItem?.isLocked == true {
                return completion([])
            } else {
                completion(["NotesIdentifier"])
            }
        }

        func indirectScribbleInteraction(_: UIInteraction, frameForElement _: String) -> CGRect {
            bounds
        }

        func indirectScribbleInteraction(_: UIInteraction, isElementFocused _: String) -> Bool {
            notesTextView != nil
        }
    }

#endif
