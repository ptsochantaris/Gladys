
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

	weak var delegate: ArchivedItemCellDelegate?

	private var deleteButton: UIButton?
	private var editHolder: UIView?

	@objc private func deleteSelected() {
		if let archivedDropItem = archivedDropItem {
			delegate?.deleteRequested(for: archivedDropItem)
		}
	}

	override func tintColorDidChange() {
		deleteButton?.tintColor = tintColor
	}

	var isEditing: Bool = false {
		didSet {
			if isEditing && editHolder == nil {

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
	}

	var archivedDropItem: ArchivedDropItem? {
		didSet {
			decorate()
		}
	}

	private var existingMapView: MiniMapView?

	override func prepareForReuse() {
		archivedDropItem = nil
		decorate()
	}

	private func decorate() {

		var wantMapView = false

		accessoryLabel.text = nil
		accessoryLabelDistance.constant = 0

		image.image = nil
		image.isHidden = true

		if let archivedDropItem = archivedDropItem {

			if archivedDropItem.isLoading {
				image.isHidden = true
				label.text = nil
				spinner.startAnimating()
			} else {
				spinner.stopAnimating()

				if !archivedDropItem.allLoadedWell {
					image.isHidden = true
					label.text = "Could not import this item"
				} else {
					image.isHidden = false
					decorateLoadedItem(archivedDropItem)
				}

				// if we're showing an icon, let's try to enahnce things a bit
				if image.contentMode == .center, let backgroundItem = archivedDropItem.backgroundInfoObject {
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
			labelDistance.constant = 0
			spinner.startAnimating()
		}

		if !wantMapView, let e = existingMapView {
			e.removeFromSuperview()
			existingMapView = nil
		}
	}

	private func decorateLoadedItem(_ item: ArchivedDropItem) {

		let info = item.displayInfo
		image.image = info.image

		switch info.imageContentMode {
		case .center:
			image.contentMode = .center
			image.circle = false
		case .fill:
			image.contentMode = .scaleAspectFill
			image.circle = false
		case .fit:
			image.contentMode = .scaleAspectFit
			image.circle = false
		case .circle:
			image.contentMode = .scaleAspectFill
			image.circle = true
		}

		if image.contentMode == .center {
			label.numberOfLines = 8
		} else {
			label.numberOfLines = 2
		}
		label.textAlignment = info.titleAlignment
		label.text = info.title

		labelDistance.constant = label.text == nil ? 0 : 8

		if let t = info.accessoryText {
			accessoryLabel.text = t
			accessoryLabelDistance.constant = 8
		}
	}

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

