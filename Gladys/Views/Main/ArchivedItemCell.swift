
import UIKit
import MapKit

final class ArchivedItemCell: UICollectionViewCell {
	@IBOutlet private weak var image: GladysImageView!
	@IBOutlet private weak var bottomLabel: UILabel!
	@IBOutlet private weak var labelsLabel: HighlightLabel!

	@IBOutlet private weak var topLabel: UILabel!
	@IBOutlet private weak var topLabelHolder: UIView!

	@IBOutlet private weak var progressView: UIProgressView!
	@IBOutlet private weak var progressViewHolder: UIView!

	@IBOutlet private weak var cancelButton: UIButton!
	@IBOutlet private weak var lockImage: UIImageView!
	@IBOutlet private weak var spinner: UIActivityIndicatorView!

	@IBOutlet private weak var topLabelLeft: NSLayoutConstraint!
	@IBOutlet private weak var labelStack: UIStackView!

	private var tickImage: UIImageView?
	private var tickHolder: UIView?
	private var shareImage: UIImageView?
	private var shareHolder: UIView?

	@IBAction private func cancelSelected(_ sender: UIButton) {
		progressView.observedProgress = nil
		if let archivedDropItem = archivedDropItem, archivedDropItem.shouldDisplayLoading {
			ViewController.shared.deleteRequested(for: [archivedDropItem])
		}
	}

	private var shareColor: UIColor? {
		if archivedDropItem?.shareMode == .sharing {
			return UIColor(named: "colorTint")
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
		labelsLabel.tintColor = c
		topLabel.highlightedTextColor = c
		bottomLabel.highlightedTextColor = c
	}

	var isSelectedForAction: Bool {
		set {
			tickImage?.isHighlighted = newValue
		}
		get {
			return tickImage?.isHighlighted ?? false
		}
	}

	override var isSelected: Bool {
		set {}
		get { return false }
	}

	override var isHighlighted: Bool {
		set {}
		get { return false }
	}

	var isEditing: Bool = false {
		didSet {
			if isEditing && tickHolder == nil && progressViewHolder.isHidden {

				let img = UIImageView(frame: .zero)
				img.translatesAutoresizingMaskIntoConstraints = false
				img.tintColor = self.tintColor
                img.preferredSymbolConfiguration = UIImage.SymbolConfiguration(scale: .large)
                img.image = UIImage(systemName: "circle")
                img.highlightedImage = UIImage(systemName: "checkmark.circle.fill")

				let holder = UIView(frame: .zero)
				holder.translatesAutoresizingMaskIntoConstraints = false
				holder.backgroundColor = borderView.backgroundColor
				holder.layer.maskedCorners = .layerMinXMaxYCorner
				holder.layer.cornerRadius = 20
				holder.addSubview(img)
				contentView.addSubview(holder)

				NSLayoutConstraint.activate([
					holder.topAnchor.constraint(equalTo: topAnchor),
					holder.trailingAnchor.constraint(equalTo: trailingAnchor),

					holder.widthAnchor.constraint(equalToConstant: 41),
					holder.heightAnchor.constraint(equalToConstant: 41),

					img.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
					img.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
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

	var shareMode: ArchivedDropItem.ShareMode = ArchivedDropItem.ShareMode.none {
		didSet {
			if oldValue == shareMode { return }
			let shouldShow = shareMode != .none
			if shouldShow, shareHolder == nil {

				let img = UIImageView(frame: .zero)
				img.translatesAutoresizingMaskIntoConstraints = false
                img.tintColor = self.tintColor
                img.preferredSymbolConfiguration = UIImage.SymbolConfiguration(scale: .large)
				img.image = UIImage(systemName: "person.crop.circle.fill.badge.checkmark")

				let holder = UIView(frame: .zero)
				holder.translatesAutoresizingMaskIntoConstraints = false
				holder.backgroundColor = borderView.backgroundColor
				holder.layer.cornerRadius = 20
				holder.layer.maskedCorners = .layerMaxXMaxYCorner
				holder.addSubview(img)
                contentView.addSubview(holder)

				NSLayoutConstraint.activate([
					holder.topAnchor.constraint(equalTo: topAnchor),
					holder.leadingAnchor.constraint(equalTo: leadingAnchor),

					holder.widthAnchor.constraint(equalToConstant: 41),
					holder.heightAnchor.constraint(equalToConstant: 41),

					img.centerXAnchor.constraint(equalTo: holder.centerXAnchor, constant: -3),
					img.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
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

	private let borderView = UIView()

	private lazy var wideCell = { return reuseIdentifier == "WideArchivedItemCell" }()

	override func awakeFromNib() {
		super.awakeFromNib()
		clipsToBounds = true
		layer.cornerRadius = 10

		image.clipsToBounds = true
		image.squircle = !wideCell
		image.accessibilityIgnoresInvertColors = true
		contentView.tintColor = UIColor(named: "colorDarkGray")

		let b = UIView()
		b.layer.cornerRadius = 10
		backgroundView = b

		labelStack.setCustomSpacing(3, after: labelsLabel)

		borderView.layer.cornerRadius = 10
        borderView.backgroundColor = backgroundColor
		b.cover(with: borderView, insets: UIEdgeInsets(top: 0, left: 0, bottom: 0.5, right: 0))
        b.backgroundColor = UIColor(named: "colorShadowContrast")

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(itemModified(_:)), name: .ItemModified, object: nil)
        n.addObserver(self, selector: #selector(itemModified(_:)), name: .IngestComplete, object: nil)

		let p = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
		contentView.addGestureRecognizer(p)
        
        let interaction = UIContextMenuInteraction(delegate: self)
        addInteraction(interaction)
	}
    
	@objc private func pinched(_ pinchRecognizer: UIPinchGestureRecognizer) {
		if pinchRecognizer.state == .changed, pinchRecognizer.velocity > 4, let item = archivedDropItem, !item.shouldDisplayLoading, item.canPreview, !item.needsUnlock {
			pinchRecognizer.state = .ended
			item.tryPreview(in: ViewController.top, from: self)
		}
	}

	var archivedDropItem: ArchivedDropItem? {
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

	var lowMemoryMode = false

	@objc private func itemModified(_ notification: Notification) {
        guard (notification.object as? ArchivedDropItem) == archivedDropItem else { return }
        if !lowMemoryMode, viewWithTag(82646) == nil, let snap = snapshotView(afterScreenUpdates: true) {
			snap.tag = 82646
            addSubview(snap)
            reDecorate()
            UIView.animate(withDuration: 0.2, delay: 0, options: [], animations: {
                snap.alpha = 0
            }) { _ in
                snap.removeFromSuperview()
            }
        } else {
            reDecorate()
        }
	}

	func reDecorate() {
		if lowMemoryMode {
			decorate(with: nil)
		} else {
			decorate(with: archivedDropItem)
		}
	}

	static func warmUp(for item: ArchivedDropItem) {
		imageProcessingQueue.async {
			let cacheKey = item.imageCacheKey
			if imageCache.object(forKey: cacheKey) == nil {
				imageCache.setObject(item.displayIcon, forKey: cacheKey)
			}
		}
	}

	private func decorate(with item: ArchivedDropItem?) {

		var wantColourView = false
		var wantMapView = false
		var hideImage = true
		var hideProgress = true
		var hideSpinner = true
		var hideLock = true
		var shared = ArchivedDropItem.ShareMode.none

		var topLabelText: String?
		var topLabelAlignment: NSTextAlignment?

		var bottomLabelText: String?
		var bottomLabelHighlight = false
		var bottomLabelAlignment: NSTextAlignment?
		var labels: [String]?

        progressView.observedProgress = nil

		if let item = item {

			if item.shouldDisplayLoading {
				if item.needsReIngest {
					hideSpinner = false
				} else {
					hideProgress = false
					progressView.observedProgress = item.loadingProgress
				}

			} else if item.needsUnlock {
				hideLock = false
				bottomLabelAlignment = .center
				bottomLabelText = item.lockHint
				shared = item.shareMode

			} else {

				hideImage = false
				shared = item.shareMode

				imageProcessingQueue.async { [weak self] in
					if let u1 = self?.archivedDropItem?.uuid, u1 == item.uuid {
						let cacheKey = item.imageCacheKey
						if let cachedImage = imageCache.object(forKey: cacheKey) {
							DispatchQueue.main.async { [weak self] in
								if let u2 = self?.archivedDropItem?.uuid, u1 == u2 {
									self?.image.image = cachedImage
								}
							}
						} else {
							let img = item.displayIcon
							imageCache.setObject(img, forKey: cacheKey)
							DispatchQueue.main.async { [weak self] in
								if let u2 = self?.archivedDropItem?.uuid, u1 == u2 {
									self?.image.image = img
								}
							}
						}
					}
				}

				let primaryLabel: UILabel
				let secondaryLabel: UILabel

				let titleInfo = item.displayText
				topLabelAlignment = titleInfo.1
				topLabelText = titleInfo.0

				if PersistedOptions.displayNotesInMainView && !item.note.isEmpty {
					bottomLabelText = item.note
					bottomLabelHighlight = true
				} else if let url = item.associatedWebURL {
					bottomLabelText = url.absoluteString
					if topLabelText == bottomLabelText {
						topLabelText = nil
					}
				}

				let H = ViewController.shared.itemSize.height
				let wideMode = H > 145
				let smallMode = H < 240

				if PersistedOptions.displayLabelsInMainView {
					labels = item.labels
				}

				if bottomLabelText == nil && topLabelText != nil {
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
						primaryLabel.numberOfLines = wideMode ? baseLines+2 : 2
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
		labelsLabel.isHidden = newLabels.isEmpty

		image.alpha = hideImage ? 0 : 1
		lockImage.isHidden = hideLock
		shareMode = shared

		let isSpinning = spinner.isAnimating
		if isSpinning && hideSpinner {
			spinner.stopAnimating()
		} else if !isSpinning && !hideSpinner {
			spinner.startAnimating()
		}

		topLabelLeft.constant = (shareHolder == nil || wideCell) ? 0 : 41
	}

	func flash() {
        let originalColor = borderView.backgroundColor
		UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
			self.borderView.backgroundColor = UIColor(named: "colorTint")
		}) { finished in
			UIView.animate(withDuration: 0.9, delay: 0, options: .curveEaseIn, animations: {
				self.borderView.backgroundColor = originalColor
            }, completion: nil)
		}
	}

	/////////////////////////////////////////

	override func accessibilityActivate() -> Bool {
		if shouldDisplayLoading {
			cancelSelected(cancelButton)
			return true
		} else {
			return super.accessibilityActivate()
		}
	}

	override var isAccessibilityElement: Bool {
		set {}
		get {
			return true
		}
	}

	override var accessibilityLabel: String? {
		set {}
		get {
			if shouldDisplayLoading {
				return nil
			}
			return (topLabel.text ?? "") + ((archivedDropItem?.isLocked ?? false) ? "\nItem Locked" : "")
		}
	}

	override var accessibilityValue: String? {
		set {}
		get {
			if shouldDisplayLoading {
				return "Processing item. Activate to cancel."
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
	}

	override var accessibilityTraits: UIAccessibilityTraits {
		set {}
		get {
			return isSelectedForAction ? .selected : .none
		}
	}

	private var shouldDisplayLoading: Bool {
		return archivedDropItem?.shouldDisplayLoading ?? false
	}
}

extension ArchivedItemCell: UIContextMenuInteractionDelegate {
    private func createShortcutActions() -> UIMenu? {
        guard let item = archivedDropItem else { return nil }
        
        func makeAction(title: String, callback: @escaping () -> Void, style: UIAction.Attributes, iconName: String?) -> UIAction {
            let a = UIAction(title: title) { _ in callback() }
            a.attributes = style
            if let iconName = iconName {
                a.image = UIImage(systemName: iconName)
            }
            return a
        }
        
        var children = [UIMenuElement]()
        
        if item.canOpen {
            children.append(makeAction(title: "Open", callback: {
                ViewController.shared.noteLastActionedItem(item)
                item.tryOpen(in: ViewController.shared.navigationController!) { _ in }
            }, style: [], iconName: "arrow.up.doc"))
        }
        
        if item.canPreview {
            children.append(makeAction(title: "Quick Look", callback: { [weak self] in
                guard let s = self else { return }
                ViewController.shared.noteLastActionedItem(item)
                item.tryPreview(in: ViewController.top, from: s)
                }, style: [], iconName: "eye"))
        }
        
        children.append(makeAction(title: "Info Panel", callback: {
            ViewController.shared.noteLastActionedItem(item)
            ViewController.shared.performSegue(withIdentifier: "showDetail", sender: item)
        }, style: [], iconName: "list.bullet.below.rectangle"))
        
        children.append(makeAction(title: "Move to Top", callback: {
            ViewController.shared.noteLastActionedItem(item)
            ViewController.shared.sendToTop(item: item)
        }, style: [], iconName: "arrow.turn.left.up"))
        
        children.append(makeAction(title: "Copy to Clipboard", callback: {
            ViewController.shared.noteLastActionedItem(item)
            item.copyToPasteboard()
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Copied.")
            }
        }, style: [], iconName: "doc.on.doc"))
        
        children.append(makeAction(title: "Duplicate", callback: {
            ViewController.shared.noteLastActionedItem(item)
            Model.duplicate(item: item)
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Duplicated.")
            }
            }, style: [], iconName: "arrow.branch"))
        
        children.append(makeAction(title: "Share", callback: { [weak self] in
            guard let s = self else { return }
            ViewController.shared.noteLastActionedItem(item)
            let a = UIActivityViewController(activityItems: [item.itemProviderForSharing], applicationActivities: nil)
            ViewController.shared.present(a, animated: true)
            if let p = a.popoverPresentationController {
                p.sourceView = s
                p.sourceRect = s.contentView.bounds.insetBy(dx: 6, dy: 6)
            }
        }, style: [], iconName: "square.and.arrow.up"))
                  
        let confirmTitle = item.shareMode == .sharing ? "Confirm (Will delete from shared users too)" : "Confirm Delete"
        let confirmAction = UIAction(title: confirmTitle) { _ in
            ViewController.shared.deleteRequested(for: [item])
        }
        confirmAction.attributes = .destructive
        confirmAction.image = UIImage(systemName: "bin.xmark")
        let deleteMenu = UIMenu(title: "Delete", image: confirmAction.image, identifier: nil, options: .destructive, children: [confirmAction])
        children.append(deleteMenu)
        
        return UIMenu(title: "", image: nil, identifier: nil, options: [], children: children)
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = archivedDropItem else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: { [weak item] in
            guard let i = item else { return nil }
            if i.canPreview, let previewItem = i.previewableTypeItem {
                if previewItem.isWebURL, let url = previewItem.encodedUrl {
                    let x = ViewController.shared.storyboard!.instantiateViewController(identifier: "LinkPreview") as! LinkViewController
                    x.url = url as URL
                    return x
                } else {
                    return previewItem.quickLook(extraRightButton: nil)
                }
            } else {
                return nil
            }
        }, actionProvider: { [weak self] _ in
            return self?.createShortcutActions()
        })
    }
}
