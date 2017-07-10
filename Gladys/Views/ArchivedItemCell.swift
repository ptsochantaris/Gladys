
import UIKit
import MapKit
import WebKit

extension UIView {
	func cover(with view: UIView, insets: UIEdgeInsets = .zero) {
		view.translatesAutoresizingMaskIntoConstraints = false
		addSubview(view)

		view.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: insets.left).isActive = true
		view.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -insets.right).isActive = true
		view.topAnchor.constraint(equalTo: self.topAnchor, constant: insets.top).isActive = true
		view.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -insets.bottom).isActive = true
	}

	func center(on parentView: UIView) {
		translatesAutoresizingMaskIntoConstraints = false
		parentView.addSubview(self)
		centerXAnchor.constraint(equalTo: parentView.centerXAnchor).isActive = true
		centerYAnchor.constraint(equalTo: parentView.centerYAnchor).isActive = true
	}

	static func animate(animations: @escaping ()->Void, completion: ((Bool)->Void)? = nil) {
		UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut, animations: animations, completion: completion)
	}
}

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
				DispatchQueue.main.async { [weak self] in
					let img = snapshot.image
					self?.image = img
					MiniMapView.cache.setObject(img, forKey: cacheKey)
					UIView.animate(withDuration: 0.2) {
						self?.alpha = 1
					}
				}
			}
			if let error = error {
				log("Error taking snapshot: \(error.localizedDescription)")
			}
		}
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}

protocol ArchivedItemCellDelegate: class {
	func deleteRequested(for: ArchivedDropItem)
}

final class ArchivedItemCell: UICollectionViewCell {
	@IBOutlet weak var image: GladysImageView!
	@IBOutlet weak var label: UILabel!
	@IBOutlet weak var labelDistance: NSLayoutConstraint!
	@IBOutlet weak var accessoryLabel: UILabel!
	@IBOutlet weak var accessoryLabelDistance: NSLayoutConstraint!
	@IBOutlet var spinner: UIActivityIndicatorView!
	@IBOutlet weak var cancelButton: UIButton!

	weak var delegate: ArchivedItemCellDelegate?

	private var deleteButton: UIButton?
	private var editHolder: UIView?

	@objc private func deleteSelected() {
		if let archivedDropItem = archivedDropItem {
			delegate?.deleteRequested(for: archivedDropItem)
		}
	}
	
	@IBAction func cancelSelected(_ sender: UIButton) {
		if let archivedDropItem = archivedDropItem {
			archivedDropItem.cancelIngest()
			delegate?.deleteRequested(for: archivedDropItem)
		}
	}

	override func tintColorDidChange() {
		deleteButton?.tintColor = tintColor
		cancelButton?.tintColor = tintColor
	}

	var isEditing: Bool = false {
		didSet {
			if isEditing && editHolder == nil && cancelButton.isHidden {

				let button = UIButton(frame: .zero)
				button.translatesAutoresizingMaskIntoConstraints = false
				button.tintColor = self.tintColor
				button.setImage(#imageLiteral(resourceName: "iconDelete"), for: .normal)
				button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
				button.addTarget(self, action: #selector(deleteSelected), for: .touchUpInside)

				let holder = UIView(frame: .zero)
				holder.translatesAutoresizingMaskIntoConstraints = false
				holder.backgroundColor = .white
				holder.layer.cornerRadius = 10
				addSubview(holder)

				holder.topAnchor.constraint(equalTo: topAnchor, constant: 0).isActive = true
				holder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0).isActive = true

				holder.widthAnchor.constraint(equalToConstant: 50).isActive = true
				holder.heightAnchor.constraint(equalToConstant: 50).isActive = true

				holder.addSubview(button)
				button.centerXAnchor.constraint(equalTo: holder.centerXAnchor).isActive = true
				button.centerYAnchor.constraint(equalTo: holder.centerYAnchor).isActive = true
				holder.cover(with: button)

				deleteButton = button
				editHolder = holder

			} else if !isEditing, let h = editHolder {
				h.removeFromSuperview()
				editHolder = nil
				deleteButton = nil
			}
		}
	}

	override func dragStateDidChange(_ dragState: UICollectionViewCellDragState) {
		super.dragStateDidChange(dragState)
		switch dragState {
		case .dragging, .lifting:
			backgroundView?.alpha = 0
		case .none:
			backgroundView?.alpha = 1
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		clipsToBounds = true
		image.clipsToBounds = true
		image.layer.cornerRadius = 5
		contentView.tintColor = .darkGray

		let b = UIView()
		b.backgroundColor = .lightGray
		b.layer.cornerRadius = 10
		backgroundView = b

		let borderView = UIView()
		borderView.backgroundColor = .white
		borderView.layer.cornerRadius = 10
		b.cover(with: borderView, insets: UIEdgeInsetsMake(0, 0, 0.5, 0))

		NotificationCenter.default.addObserver(self, selector: #selector(lowMemoryModeOn), name: .LowMemoryModeOn, object: nil)
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

	private var existingMapView: MiniMapView?

	var lowMemoryMode = false

	func reDecorate() {
		if lowMemoryMode {
			decorate(with: nil)
		} else {
			decorate(with: archivedDropItem)
		}
	}

	private static let displayIconCache = NSCache<NSString, UIImage>()

	private func decorate(with item: ArchivedDropItem?) {

		var wantMapView = false
		var hideCancel = true
		var hideImage = true
		var showSpinner = false

		var accessoryLabelText: String?
		var accessoryLabelDistanceConstant: CGFloat = 0

		if let item = item {

			if item.isLoading {
				let count = item.loadCount
				label.text = count > 1 ? "\(count) items left to transfer" : "Completing transfer"
				hideCancel = false
				showSpinner = true
				image.image = nil
			} else {
				hideImage = false

				let cacheKey = item.uuid.uuidString as NSString
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

				switch item.displayMode {
				case .center:
					image.contentMode = .center
					image.circle = false
					label.numberOfLines = 8
				case .fill:
					image.contentMode = .scaleAspectFill
					image.circle = false
					label.numberOfLines = 2
				case .fit:
					image.contentMode = .scaleAspectFit
					image.circle = false
					label.numberOfLines = 2
				case .circle:
					image.contentMode = .scaleAspectFill
					image.circle = true
					label.numberOfLines = 2
				}

				let titleInfo = item.displayTitle
				label.textAlignment = titleInfo.1
				label.text = titleInfo.0

				if let t = item.accessoryTitle {
					accessoryLabelText = t
					accessoryLabelDistanceConstant = 8
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
						image.backgroundColor = color // TODO - perhaps a custom view over the curent one
					}
				}
			}

		} else { // item is nil
			label.text = nil
			image.image = nil
		}

		if !wantMapView, let e = existingMapView {
			e.removeFromSuperview()
			existingMapView = nil
		}

		if showSpinner && !spinner.isAnimating {
			spinner.startAnimating()
		} else if !showSpinner && spinner.isAnimating {
			spinner.stopAnimating()
		}
		
		accessoryLabel.text = accessoryLabelText
		labelDistance.constant = (label.text == nil) ? 0 : 8
		accessoryLabelDistance.constant = accessoryLabelDistanceConstant
		image.isHidden = hideImage
		cancelButton.isHidden = hideCancel
	}

	private static let imageProcessingQueue = DispatchQueue(label: "build.bru.Gladys.imageProcessing", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

	func flash() {
		UIView.animate(withDuration: 0.6, delay: 0, options: .curveEaseOut, animations: {
			self.backgroundColor = .red
		}) { finished in
			UIView.animate(withDuration: 0.6, delay: 0, options: .curveEaseIn, animations: {
				self.backgroundColor = .white
			}) { finished in
			}
		}
	}
}

