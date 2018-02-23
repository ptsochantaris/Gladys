
import UIKit
import MapKit
import WebKit

final class GladysImageView: UIImageView {

	var circle: Bool = false {
		didSet {
			if oldValue != circle {
				setNeedsLayout()
			}
		}
	}

	private var aspectLock: NSLayoutConstraint?

	override func layoutSubviews() {
		super.layoutSubviews()

		if circle {
			let smallestSide = min(bounds.size.width, bounds.size.height)
			layer.cornerRadius = (smallestSide * 0.5).rounded(.down)
			if let a = aspectLock {
				a.constant = smallestSide
			} else {
				aspectLock = widthAnchor.constraint(equalToConstant: smallestSide)
				aspectLock?.isActive = true
			}

		} else {
			layer.cornerRadius = 5
			if let a = aspectLock {
				removeConstraint(a)
				aspectLock = nil
			}
		}
	}
}

final class MiniMapView: UIImageView {

	private var coordinate: CLLocationCoordinate2D?
	private static let cache = NSCache<NSString, UIImage>()
	private weak var snapshotter: MKMapSnapshotter?
	private var snapshotOptions: MKMapSnapshotOptions?

	func show(location: MKMapItem) {

		let newCoordinate = location.placemark.coordinate
		if let coordinate = coordinate,
			newCoordinate.latitude == coordinate.latitude,
			newCoordinate.longitude == coordinate.longitude { return }

		image = nil
		coordinate = newCoordinate
		setNeedsLayout()
	}

	init(at location: MKMapItem) {
		super.init(frame: .zero)
		contentMode = .center
		show(location: location)
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		guard let coordinate = coordinate else { return }
		if bounds.isEmpty { return }
		if let image = image, image.size == bounds.size { return }
		if UIApplication.shared.applicationState == .background { return }

		let cacheKey = NSString(format: "%f %f %f %f", coordinate.latitude, coordinate.longitude, bounds.size.width, bounds.size.height)
		if let existingImage = MiniMapView.cache.object(forKey: cacheKey) {
			image = existingImage
			return
		}

		if let o = snapshotOptions {
			if !(o.region.center.latitude != coordinate.latitude || o.region.center.longitude != coordinate.longitude || o.size != bounds.size) {
				return
			}
		}

		alpha = 0
		snapshotter?.cancel()
		snapshotter = nil
		snapshotOptions = nil

		let O = MKMapSnapshotOptions()
		O.region = MKCoordinateRegionMakeWithDistance(coordinate, 200.0, 200.0)
		O.showsBuildings = true
		O.showsPointsOfInterest = true
		O.size = bounds.size
		snapshotOptions = O

		let S = MKMapSnapshotter(options: O)
		snapshotter = S

		S.start { snapshot, error in
			if let snapshot = snapshot {
				let img = snapshot.image
				MiniMapView.cache.setObject(img, forKey: cacheKey)
				DispatchQueue.main.async { [weak self] in
					self?.image = img
					UIView.animate(withDuration: 0.2) {
						self?.alpha = 1
					}
				}
			}
			if let error = error {
				log("Error taking snapshot: \(error.finalDescription)")
			}
		}
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	static func clearCaches() {
		cache.removeAllObjects()
	}
}

final class ArchivedItemCell: UICollectionViewCell {
	@IBOutlet weak var image: GladysImageView!
	@IBOutlet weak var bottomLabel: UILabel!
	@IBOutlet weak var bottomLabelDistance: NSLayoutConstraint!
	@IBOutlet weak var topLabel: UILabel!
	@IBOutlet weak var topLabelDistance: NSLayoutConstraint!
	@IBOutlet weak var progressView: UIProgressView!
	@IBOutlet weak var cancelButton: UIButton!

	private var selectionImage: UIImageView?
	private var editHolder: UIView?

	@IBAction func cancelSelected(_ sender: UIButton) {
		progressView.observedProgress = nil
		if let archivedDropItem = archivedDropItem, archivedDropItem.shouldDisplayLoading {
			ViewController.shared.deleteRequested(for: [archivedDropItem])
		}
	}

	override func tintColorDidChange() {
		selectionImage?.tintColor = tintColor
		cancelButton?.tintColor = tintColor
		topLabel.highlightedTextColor = tintColor
		bottomLabel.highlightedTextColor = tintColor
	}

	@objc private func darkModeChanged() {
		borderView.backgroundColor = borderViewColor
		topLabel.textColor = plainTextColor
		bottomLabel.textColor = plainTextColor
		if PersistedOptions.darkMode {
			tintColor = .white
			backgroundView?.backgroundColor = .darkGray
			image.backgroundColor = UIColor(white: 0.2, alpha: 1)
		} else {
			tintColor = nil
			backgroundView?.backgroundColor = .lightGray
			image.backgroundColor = ViewController.imageLightBackground
		}
		if isEditing {
			let wasSelected = selectionImage?.isHighlighted ?? false
			isEditing = false
			isEditing = true
			if wasSelected {
				selectionImage?.isHighlighted = true
			}
		}
	}

	var isSelectedForAction: Bool {
		set {
			selectionImage?.isHighlighted = newValue
		}
		get {
			return selectionImage?.isHighlighted ?? false
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
			if isEditing && editHolder == nil && cancelButton.isHidden {

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

				selectionImage = img
				editHolder = holder

			} else if !isEditing, let h = editHolder {
				h.removeFromSuperview()
				selectionImage = nil
				editHolder = nil
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

	private static let darkTextColor: UIColor = {
		return UIColor(red: 76.0/255.0, green: 76.0/255.0, blue: 76.0/255.0, alpha: 1)
	}()

	private static let lightTextColor: UIColor = {
		return UIColor(red: 200.0/255.0, green: 200.0/255.0, blue: 200.0/255.0, alpha: 1)
	}()

	override func awakeFromNib() {
		super.awakeFromNib()
		clipsToBounds = true
		image.clipsToBounds = true
		image.layer.cornerRadius = 5
		image.accessibilityIgnoresInvertColors = true
		contentView.tintColor = .darkGray

		ViewController.imageLightBackground = image.backgroundColor

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
		if pinchRecognizer.state == .changed, pinchRecognizer.velocity > 4, let item = archivedDropItem, !item.shouldDisplayLoading, item.canPreview {
			pinchRecognizer.state = .ended
			clearAllOtherGestures()
			item.tryPreview(in: ViewController.shared.navigationController!, from: self)
		}
	}

	@objc private func deepPressed(_ deepPressRecognizer: DeepPressGestureRecognizer) {
		if let item = archivedDropItem, deepPressRecognizer.state == .began, !item.shouldDisplayLoading {
			clearAllOtherGestures()
			showShortcutMenu(item: item, push: true)
		}
	}

	@objc private func doubleTapped(_ tapRecognizer: UITapGestureRecognizer) {
		if let item = archivedDropItem, tapRecognizer.state == .ended, !item.shouldDisplayLoading {
			clearAllOtherGestures()
			showShortcutMenu(item: item, push: false)
		}
	}

	private func showShortcutMenu(item: ArchivedDropItem, push: Bool) {
		let title = item.addedString
		let subtitle = item.note.isEmpty ? nil : item.note
		let a = UIAlertController(title: title, message: subtitle, preferredStyle: .actionSheet)
		if item.canOpen {
			a.addAction(UIAlertAction(title: "Open", style: .default, handler: { _ in
				self.egress()
				item.tryOpen(in: ViewController.shared.navigationController!) { _ in }
			}))
		}
		if item.canPreview {
			a.addAction(UIAlertAction(title: "Quick Look", style: .default, handler: { _ in
				self.egress()
				item.tryPreview(in: ViewController.shared.navigationController!, from: self)
			}))
		}
		a.addAction(UIAlertAction(title: "Move to Top", style: .default, handler: { _ in
			self.egress()
			ViewController.shared.sendToTop(item: item)
		}))
		a.addAction(UIAlertAction(title: "Copy to Clipboard", style: .default, handler: { _ in
			self.egress()
			item.copyToPasteboard()
		}))
		a.addAction(UIAlertAction(title: "Share", style: .default, handler: { _ in
			self.egress()
			let a = UIActivityViewController(activityItems: item.shareableComponents, applicationActivities: nil)
			ViewController.shared.present(a, animated: true)
			if let p = a.popoverPresentationController {
				p.sourceView = self
				p.sourceRect = self.contentView.bounds.insetBy(dx: 6, dy: 6)
			}
		}))
		a.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
			self.egress()
			self.confirmDelete(for: item, push: push)
		}))
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
		(ViewController.shared.presentedViewController ?? ViewController.shared).present(a, animated: true)
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
	}

	private var existingMapView: MiniMapView?

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

		var wantMapView = false
		var hideCancel = true
		var hideImage = true
		var hideProgress = true

		var topLabelText: String?
		var topLabelAlignment: NSTextAlignment?

		var bottomLabelText: String?
		var bottomLabelHighlight = false
		var bottomLabelAlignment: NSTextAlignment?

		if let item = item {

			if item.shouldDisplayLoading {
				hideCancel = false
				hideProgress = false
				progressView.observedProgress = item.loadingProgress
				image.image = nil

			} else {

				hideImage = false
				progressView.observedProgress = nil

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
					primaryLabel.numberOfLines = ViewController.shared.itemSize.height > 145 ? 8 : 2
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
						if let m = existingMapView {
							m.show(location: mapItem)
						} else {
							let m = MiniMapView(at: mapItem)
							image.cover(with: m)
							existingMapView = m
						}

					} else if let color = backgroundItem as? UIColor {
						image.backgroundColor = color // TODO - perhaps a custom view over the current one
					}
				}
			}

		} else { // item is nil
			image.image = nil
			progressView.observedProgress = nil
		}

		if !wantMapView, let e = existingMapView {
			e.removeFromSuperview()
			existingMapView = nil
		}

		progressView.isHidden = hideProgress

		topLabel.text = topLabelText
		topLabelDistance.constant = (topLabelText == nil) ? 0 : 7
		topLabel.textAlignment = topLabelAlignment ?? .center

		bottomLabel.text = bottomLabelText
		bottomLabelDistance.constant = (bottomLabelText == nil) ? 0 : 7
		bottomLabel.textAlignment = bottomLabelAlignment ?? .center
		bottomLabel.isHighlighted = bottomLabelHighlight

		image.isHidden = hideImage
		cancelButton.isHidden = hideCancel
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
		UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseInOut, animations: {
			self.transform = .identity
		})
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
			return topLabel.text
		}
	}

	override var accessibilityValue: String? {
		set {}
		get {
			if shouldDisplayLoading {
				return "Processing item. Activate to cancel."
			} else {
				return [archivedDropItem?.dominantTypeDescription, image.accessibilityLabel, image.accessibilityValue, bottomLabel.text].flatMap { $0 }.joined(separator: "\n")
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

