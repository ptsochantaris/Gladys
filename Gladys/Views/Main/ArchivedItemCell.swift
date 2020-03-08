import UIKit
import MapKit
import CloudKit

final class ArchivedItemCell: UICollectionViewCell {
    
	@IBOutlet private weak var image: GladysImageView!
	@IBOutlet private weak var bottomLabel: UILabel!
	@IBOutlet private weak var labelsLabel: HighlightLabel!
    @IBOutlet private weak var labelsHolder: UIView!
    
    @IBOutlet private weak var container: UIView!

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
    
    var dragParameters: UIDragPreviewParameters {
        let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 8, height: 8))
        let params = UIDragPreviewParameters()
        params.visiblePath = path
        return params
    }

	@IBAction private func cancelSelected(_ sender: UIButton) {
		progressView.observedProgress = nil
		if let archivedDropItem = archivedDropItem, archivedDropItem.shouldDisplayLoading {
            Model.delete(items: [archivedDropItem])
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
                img.tintColor = self.tintColor
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
    
	private lazy var wideCell = { return reuseIdentifier == "WideArchivedItemCell" }()

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        container.layer.borderColor = UIColor.opaqueSeparator.cgColor
    }
    
	override func awakeFromNib() {
		super.awakeFromNib()
        
        container.layer.cornerRadius = 10
        container.layer.borderWidth = 1.0 / UIScreen.main.scale
        container.layer.borderColor = UIColor.opaqueSeparator.cgColor

        image.wideMode = wideCell
		image.accessibilityIgnoresInvertColors = true

		labelStack.setCustomSpacing(4, after: labelsHolder)

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(itemModified(_:)), name: .ItemModified, object: nil)
        n.addObserver(self, selector: #selector(itemModified(_:)), name: .IngestComplete, object: nil)

		let p = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
		container.addGestureRecognizer(p)
	}
    
	@objc private func pinched(_ pinchRecognizer: UIPinchGestureRecognizer) {
        if pinchRecognizer.state == .changed, pinchRecognizer.velocity > 4, let item = archivedDropItem, !item.shouldDisplayLoading, item.canPreview, !item.flags.contains(.needsUnlock) {
			pinchRecognizer.state = .ended
            if let presenter = window?.alertPresenter {
                item.tryPreview(in: presenter, from: self)
            }
		}
	}

	var archivedDropItem: ArchivedItem? {
		didSet {
			reDecorate()
		}
	}
    
	override func prepareForReuse() {
		super.prepareForReuse()
		progressView.observedProgress = nil
		progressView.progress = 0
		image.image = nil
        if let size = window?.windowScene?.session.userInfo?["ItemSize"] as? CGSize {
            itemSize = size
        }
	}

    deinit {
        progressView.observedProgress = nil
    }
    
	private var existingPreviewView: UIView?

	var lowMemoryMode = false

	@objc private func itemModified(_ notification: Notification) {
        guard (notification.object as? ArchivedItem) == archivedDropItem else { return }
        if !lowMemoryMode, viewWithTag(82646) == nil, let snap = snapshotView(afterScreenUpdates: true) {
			snap.tag = 82646
            addSubview(snap)
            reDecorate()
            UIView.animate(withDuration: 0.2, delay: 0, options: [], animations: {
                snap.alpha = 0
            }, completion: { _ in
                snap.removeFromSuperview()
            })
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

	static func warmUp(for item: ArchivedItem) {
		imageProcessingQueue.async {
			let cacheKey = item.imageCacheKey
			if imageCache.object(forKey: cacheKey) == nil {
				imageCache.setObject(item.displayIcon, forKey: cacheKey)
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

		if let item = item {

			if item.shouldDisplayLoading {
                if item.needsReIngest || item.flags.contains(.isBeingCreatedBySync) {
					hideSpinner = false
				} else {
					hideProgress = false
					progressView.observedProgress = item.loadingProgress
				}

			} else if item.flags.contains(.needsUnlock) {
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

                let H = itemSize.height
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
		labelsHolder.isHidden = newLabels.isEmpty

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
    
    private var itemSize = CGSize(width: 200, height: 200)
    
	func flash() {
        let originalColor = container.backgroundColor
        let topColor = topLabel.textColor
        let bottomColor = bottomLabel.textColor
		UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
			self.container.backgroundColor = UIColor(named: "colorTint")
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
            cancelSelected(cancelButton)
            return true
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
		return archivedDropItem?.loadingProgress != nil
	}
    
    var targetedPreviewItem: UITargetedPreview {
        return UITargetedPreview(view: container)
    }
}
