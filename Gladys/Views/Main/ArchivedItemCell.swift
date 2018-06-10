
import UIKit
import MapKit
import WebKit

struct ShortcutAction {
	let title: String
	let callback: ()->Void
	let style: UIAlertActionStyle
	let push: Bool
}

final class ArchivedItemCell: UICollectionViewCell {
	@IBOutlet weak var image: GladysImageView!
	@IBOutlet weak var bottomLabel: UILabel!
	@IBOutlet weak var labelsLabel: HighlightLabel!
	@IBOutlet weak var bottomLabelDistance: NSLayoutConstraint!
	@IBOutlet weak var topLabel: UILabel!
	@IBOutlet weak var topLabelDistance: NSLayoutConstraint!
	@IBOutlet weak var progressView: UIProgressView!
	@IBOutlet weak var cancelButton: UIButton!
	@IBOutlet weak var lockImage: UIImageView!
	@IBOutlet weak var mergeImage: UIImageView!
	@IBOutlet weak var labelsDistance: NSLayoutConstraint!

	@IBOutlet weak var topLabelLeft: NSLayoutConstraint!

	private var tickImage: UIImageView?
	private var tickHolder: UIView?
	private var shareImage: UIImageView?
	private var shareHolder: UIView?

	@IBAction func cancelSelected(_ sender: UIButton) {
		progressView.observedProgress = nil
		if let archivedDropItem = archivedDropItem, archivedDropItem.shouldDisplayLoading {
			ViewController.shared.deleteRequested(for: [archivedDropItem])
		}
	}

	private var shareColor: UIColor? {
		if archivedDropItem?.shareMode == .sharing {
			return ViewController.tintColor
		} else {
			return image.backgroundColor
		}
	}

	override func tintColorDidChange() {
		let c = tintColor
		tickImage?.tintColor = c
		shareImage?.tintColor = shareColor
		cancelButton?.tintColor = c
		lockImage.tintColor = c
		mergeImage.tintColor = c
		labelsLabel.tintColor = c
		topLabel.highlightedTextColor = c
		bottomLabel.highlightedTextColor = c
	}

	@objc private func darkModeChanged() {
		borderView.backgroundColor = borderViewColor
		topLabel.textColor = plainTextColor
		bottomLabel.textColor = plainTextColor
		if PersistedOptions.darkMode {
			tintColor = .white
			backgroundView?.backgroundColor = .darkGray
			image.backgroundColor = #colorLiteral(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
		} else {
			tintColor = nil
			backgroundView?.backgroundColor = .lightGray
			image.backgroundColor = ViewController.imageLightBackground
		}
		shareImage?.tintColor = shareColor
		shareHolder?.backgroundColor = borderView.backgroundColor
		tickHolder?.backgroundColor = borderView.backgroundColor
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
			if isEditing && tickHolder == nil && cancelButton.isHidden {

				let img = UIImageView(frame: .zero)
				img.translatesAutoresizingMaskIntoConstraints = false
				img.tintColor = self.tintColor
				img.contentMode = .center
				img.image = #imageLiteral(resourceName: "checkmark")
				img.highlightedImage = #imageLiteral(resourceName: "checkmarkSelected")

				let holder = UIView(frame: .zero)
				holder.translatesAutoresizingMaskIntoConstraints = false
				holder.backgroundColor = borderView.backgroundColor
				holder.layer.cornerRadius = 10
				holder.addSubview(img)
				addSubview(holder)

				NSLayoutConstraint.activate([
					holder.topAnchor.constraint(equalTo: topAnchor, constant: 0),
					holder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),

					holder.widthAnchor.constraint(equalToConstant: 50),
					holder.heightAnchor.constraint(equalToConstant: 50),

					img.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
					img.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
					img.widthAnchor.constraint(equalToConstant: img.image!.size.width),
					img.heightAnchor.constraint(equalToConstant: img.image!.size.height),
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

				topLabelLeft.constant = 50
				if shareHolder == nil {
					let img = UIImageView(frame: .zero)
					img.translatesAutoresizingMaskIntoConstraints = false
					img.contentMode = .center
					img.tintColor = shareColor
					img.image = #imageLiteral(resourceName: "iconUserChecked")

					let holder = UIView(frame: .zero)
					holder.translatesAutoresizingMaskIntoConstraints = false
					holder.backgroundColor = borderView.backgroundColor
					holder.layer.cornerRadius = 10
					holder.addSubview(img)
					addSubview(holder)

					NSLayoutConstraint.activate([
						holder.topAnchor.constraint(equalTo: topAnchor, constant: 0),
						holder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),

						holder.widthAnchor.constraint(equalToConstant: 50),
						holder.heightAnchor.constraint(equalToConstant: 50),

						img.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
						img.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
						img.widthAnchor.constraint(equalToConstant: img.image!.size.width),
						img.heightAnchor.constraint(equalToConstant: img.image!.size.height),
						])

					shareImage = img
					shareHolder = holder
				}
				

			} else if !shouldShow, let h = shareHolder {
				topLabelLeft.constant = 0
				h.removeFromSuperview()
				shareImage = nil
				shareHolder = nil
			}
		}
	}

	private let borderView = UIView()

	private var borderViewColor: UIColor {
		return PersistedOptions.darkMode ? .darkGray : .white
	}

	private var plainTextColor: UIColor {
		if PersistedOptions.darkMode {
			return ArchivedItemCell.lightTextColor
		} else {
			return ArchivedItemCell.darkTextColor
		}
	}

	private static let darkTextColor = #colorLiteral(red: 0.2980392157, green: 0.2980392157, blue: 0.2980392157, alpha: 1)

	private static let lightTextColor = #colorLiteral(red: 0.7843137255, green: 0.7843137255, blue: 0.7843137255, alpha: 1)

	override func awakeFromNib() {
		super.awakeFromNib()
		clipsToBounds = true
		image.clipsToBounds = true
		image.layer.cornerRadius = 5
		image.accessibilityIgnoresInvertColors = true
		contentView.tintColor = .darkGray

		let b = UIView()
		b.layer.cornerRadius = 10
		backgroundView = b

		darkModeChanged()
		borderView.layer.cornerRadius = 10
		b.cover(with: borderView, insets: UIEdgeInsetsMake(0, 0, 0.5, 0))

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(itemModified(_:)), name: .ItemModified, object: nil)
		n.addObserver(self, selector: #selector(lowMemoryModeOn), name: .LowMemoryModeOn, object: nil)
		n.addObserver(self, selector: #selector(darkModeChanged), name: .DarkModeChanged, object: nil)

		let p = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
		contentView.addGestureRecognizer(p)

		if ViewController.shared.traitCollection.forceTouchCapability == .available {
			let d = DeepPressGestureRecognizer(target: self, action: #selector(deepPressed(_:)), threshold: 0.9)
			contentView.addGestureRecognizer(d)
		} else {
			let D = UILongPressGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
			D.numberOfTouchesRequired = 2
			D.require(toFail: p)
			D.minimumPressDuration = 0.01
			contentView.addGestureRecognizer(D)
		}
	}

	private func clearAllOtherGestures() {
		let A = ViewController.shared.archivedItemCollectionView!
		for r in A.gestureRecognizers ?? [] {
			r.state = .failed
		}
	}

	@objc private func pinched(_ pinchRecognizer: UIPinchGestureRecognizer) {
		if pinchRecognizer.state == .changed, pinchRecognizer.velocity > 4, let item = archivedDropItem, !item.shouldDisplayLoading, item.canPreview, !item.needsUnlock {
			pinchRecognizer.state = .ended
			clearAllOtherGestures()
			item.tryPreview(in: ViewController.shared.navigationController!, from: self)
		}
	}

	@objc private func deepPressed(_ deepPressRecognizer: DeepPressGestureRecognizer) {
		if let item = archivedDropItem, deepPressRecognizer.state == .began, !item.shouldDisplayLoading, !item.needsUnlock {
			clearAllOtherGestures()
			showShortcutMenu(push: true)
		}
	}

	@objc private func doubleTapped(_ tapRecognizer: UITapGestureRecognizer) {
		if let item = archivedDropItem, tapRecognizer.state == .ended, !item.shouldDisplayLoading, !item.needsUnlock {
			clearAllOtherGestures()
			showShortcutMenu(push: false)
		}
	}

	private func shortcutActions(push: Bool) -> [ShortcutAction] {
		var actions = [ShortcutAction]()
		guard let item = archivedDropItem else { return actions }
		if item.canOpen {
			actions.append(ShortcutAction(title: "Open", callback: { [weak self] in
				guard let s = self else { return }
				s.egress()
				item.tryOpen(in: ViewController.shared.navigationController!) { _ in }
			}, style: .default, push: push))
		}
		if item.canPreview {
			actions.append(ShortcutAction(title: "Quick Look", callback: { [weak self] in
				guard let s = self else { return }
				s.egress()
				item.tryPreview(in: ViewController.shared.navigationController!, from: s)
			}, style: .default, push: push))
		}
		actions.append(ShortcutAction(title: "Move to Top", callback: { [weak self] in
			guard let s = self else { return }
			s.egress()
			ViewController.shared.sendToTop(item: item)
		}, style: .default, push: push))
		actions.append(ShortcutAction(title: "Copy to Clipboard", callback: { [weak self] in
			guard let s = self else { return }
			s.egress()
			item.copyToPasteboard()
			if UIAccessibilityIsVoiceOverRunning() {
				UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, "Copied.")
			}
		}, style: .default, push: push))
		actions.append(ShortcutAction(title: "Share", callback: { [weak self] in
			guard let s = self else { return }
			s.egress()
			let a = UIActivityViewController(activityItems: [item.itemProviderForSharing], applicationActivities: nil)
			ViewController.shared.present(a, animated: true)
			if let p = a.popoverPresentationController {
				p.sourceView = s
				p.sourceRect = s.contentView.bounds.insetBy(dx: 6, dy: 6)
			}
		}, style: .default, push: push))
		if !item.isImportedShare {
			actions.append(ShortcutAction(title: "Delete", callback: { [weak self] in
				guard let s = self else { return }
				s.egress()
				s.confirmDelete(for: item, push: push)
			}, style: .destructive, push: push))
		}
		return actions
	}

	private func showShortcutMenu(push: Bool) {
		guard let item = archivedDropItem else { return }
		let title = item.addedString
		let subtitle = item.note.isEmpty ? nil : item.note
		let a = UIAlertController(title: title, message: subtitle, preferredStyle: .actionSheet)
		for action in shortcutActions(push: push) {
			a.addAction(UIAlertAction(title: action.title, style: action.style, handler: { _ in action.callback() }))
		}
		presentAlert(a, push: push)
	}

	private func confirmDelete(for item: ArchivedDropItem, push: Bool) {
		let a = UIAlertController(title: "Please Confirm", message: nil, preferredStyle: .actionSheet)
		a.addAction(UIAlertAction(title: "Delete Item", style: .destructive, handler: { _ in
			ViewController.shared.deleteRequested(for: [item])
		}))
		presentAlert(a, push: push)
	}

	private func presentAlert(_ a: UIAlertController, push: Bool) {
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
			self.egress()
		}))
		a.modalPresentationStyle = .popover
		ViewController.top.present(a, animated: true)
		if let p = a.popoverPresentationController {
			p.sourceView = self
			p.sourceRect = self.contentView.bounds.insetBy(dx: 6, dy: 6)
		}
		if push {
			a.transitionCoordinator?.animate(alongsideTransition: { context in
				self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
			}, completion: nil)
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@objc private func lowMemoryModeOn() {
		lowMemoryMode = true
		reDecorate()
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
		mergeMode = false
	}

	private var existingPreviewView: UIView?

	var lowMemoryMode = false

	@objc private func itemModified(_ notification: Notification) {
		if (notification.object as? ArchivedDropItem) == archivedDropItem {
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

	private static let displayIconCache = NSCache<NSString, UIImage>()

	static func clearCaches() {
		displayIconCache.removeAllObjects()
		MiniMapView.clearCaches()
	}

	static func clearCachedImage(for item: ArchivedDropItem) {
		displayIconCache.removeObject(forKey: item.imageCacheKey)
	}

	private func decorate(with item: ArchivedDropItem?) {

		var wantColourView = false
		var wantMapView = false
		var hideCancel = true
		var hideImage = true
		var hideProgress = true
		var hideLock = true
		var hideMerge = true
		var shared = ArchivedDropItem.ShareMode.none

		var topLabelText: String?
		var topLabelAlignment: NSTextAlignment?

		var bottomLabelText: String?
		var bottomLabelHighlight = false
		var bottomLabelAlignment: NSTextAlignment?
		var labels: [String]?

		if let item = item {

			if item.shouldDisplayLoading {
				hideCancel = false
				hideProgress = false
				progressView.observedProgress = item.loadingProgress
				image.image = nil

			} else if item.needsUnlock {
				hideLock = false
				image.image = nil
				bottomLabelAlignment = .center
				bottomLabelText = item.lockHint

			} else if mergeMode {
				hideMerge = false
				hideImage = true
				image.image = nil
				topLabelAlignment = .center
				topLabelText = "Add data component"

			} else {

				hideImage = false
				progressView.observedProgress = nil
				shared = item.shareMode

				let cacheKey = item.imageCacheKey
				if let cachedImage = ArchivedItemCell.displayIconCache.object(forKey: cacheKey) {
					image.image = cachedImage
				} else {
					image.image = nil
					ArchivedItemCell.imageProcessingQueue.async { [weak self] in
						if let u1 = self?.archivedDropItem?.uuid, u1 == item.uuid {
							let img = item.displayIcon
							ArchivedItemCell.displayIconCache.setObject(img, forKey: cacheKey)
							DispatchQueue.main.sync { [weak self] in
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

				let wideMode = ViewController.shared.itemSize.height > 145

				if wideMode && PersistedOptions.displayLabelsInMainView {
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

				switch item.displayMode {
				case .center:
					image.contentMode = .center
					image.circle = false
					primaryLabel.numberOfLines = wideMode ? 8 : 2
					secondaryLabel.numberOfLines = 2
				case .fill:
					image.contentMode = .scaleAspectFill
					image.circle = false
					primaryLabel.numberOfLines = 6
					secondaryLabel.numberOfLines = 2
				case .fit:
					image.contentMode = .scaleAspectFit
					image.circle = false
					primaryLabel.numberOfLines = 6
					secondaryLabel.numberOfLines = 2
				case .circle:
					image.contentMode = .scaleAspectFill
					image.circle = true
					primaryLabel.numberOfLines = 6
					secondaryLabel.numberOfLines = 2
				}

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
			progressView.observedProgress = nil
		}

		if !(wantColourView || wantMapView), let e = existingPreviewView {
			e.removeFromSuperview()
			existingPreviewView = nil
		}

		progressView.isHidden = hideProgress

		topLabel.text = topLabelText
		topLabelDistance.constant = (topLabelText == nil) ? 0 : 7
		topLabel.textAlignment = topLabelAlignment ?? .center

		bottomLabel.text = bottomLabelText
		bottomLabelDistance.constant = (bottomLabelText == nil) ? 0 : 7
		bottomLabel.textAlignment = bottomLabelAlignment ?? .center
		bottomLabel.isHighlighted = bottomLabelHighlight

		if let labels = labels {
			labelsDistance.constant = 3
			labelsLabel.labels = labels
		} else {
			labelsDistance.constant = 0
			labelsLabel.labels = []
		}

		image.isHidden = hideImage
		cancelButton.isHidden = hideCancel
		lockImage.isHidden = hideLock
		mergeImage.isHidden = hideMerge
		shareMode = shared
	}

	private static let imageProcessingQueue = DispatchQueue(label: "build.bru.Gladys.imageProcessing", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

	func flash() {
		UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
			self.borderView.backgroundColor = .red
		}) { finished in
			UIView.animate(withDuration: 0.9, delay: 0, options: .curveEaseIn, animations: {
				self.borderView.backgroundColor = self.borderViewColor
			}) { finished in
			}
		}
	}

	private func egress() {
		if let a = archivedDropItem {
			ViewController.shared.noteLastActionedItem(a)
		}
		UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseInOut, animations: {
			self.transform = .identity
		})
	}

	var mergeMode: Bool = false {
		didSet {
			if mergeMode != oldValue {
				reDecorate()
			}
		}
	}

	@objc private func performShortcut(_ sender: UIAccessibilityCustomAction) -> Bool {
		guard let action = shortcutActions(push: false).first(where: { $0.title == sender.name }) else { return false }
		action.callback()
		return true
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

	override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
		set {}
		get {
			return shortcutActions(push: false).map {
				UIAccessibilityCustomAction(name: $0.title, target: self, selector: #selector(performShortcut(_:)))
			}
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
			return isSelectedForAction ? UIAccessibilityTraitSelected : UIAccessibilityTraitNone
		}
	}

	private var shouldDisplayLoading: Bool {
		return archivedDropItem?.shouldDisplayLoading ?? false
	}
}

