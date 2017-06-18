
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

protocol LoadCompletionDelegate: class {
	func loadCompleted(success: Bool)
}

final class MiniMapView: UIImageView {

	private let coordinate: CLLocationCoordinate2D

	init(at location: MKMapItem) {
		coordinate = location.placemark.coordinate
		super.init(frame: .zero)
		contentMode = .center
		self.alpha = 0
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		if bounds.isEmpty { return }

		if let image = image, image.size == bounds.size { return }

		let options = MKMapSnapshotOptions()
		options.region = MKCoordinateRegionMakeWithDistance(coordinate, 200.0, 200.0)
		options.showsBuildings = true
		options.showsPointsOfInterest = true
		options.size = bounds.size
		let snapshotter = MKMapSnapshotter(options: options)
		snapshotter.start { snapshot, error in
			if let snapshot = snapshot {
				DispatchQueue.main.async { [weak self] in
					self?.image = snapshot.image
					UIView.animate(withDuration: 0.2) {
						self?.alpha = 1
					}
				}
			}
			if let error = error {
				NSLog("Error taking snapshot: \(error.localizedDescription)")
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

final class ArchivedItemCell: UICollectionViewCell, LoadCompletionDelegate {
	@IBOutlet weak var image: UIImageView!
	@IBOutlet weak var label: UILabel!
	@IBOutlet weak var accessoryLabel: UILabel!
	@IBOutlet weak var accessoryLabelDistance: NSLayoutConstraint!
	@IBOutlet var spinner: UIActivityIndicatorView!

	weak var delegate: ArchivedItemCellDelegate?

	private lazy var deleteButton: UIButton = {
		let b = UIButton(frame: .zero)
		b.translatesAutoresizingMaskIntoConstraints = false
		b.tintColor = .white
		b.setImage(#imageLiteral(resourceName: "iconDelete"), for: .normal)
		b.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
		b.addTarget(self, action: #selector(deleteSelected), for: .touchUpInside)
		return b
	}()

	@objc private func deleteSelected() {
		if let archivedDropItem = archivedDropItem {
			delegate?.deleteRequested(for: archivedDropItem)
		}
	}

	var isEditing: Bool = false {
		didSet {
			if isEditing && deleteButton.superview == nil {

				let holder = UIView(frame: .zero)
				holder.translatesAutoresizingMaskIntoConstraints = false
				holder.backgroundColor = .red
				addSubview(holder)

				holder.topAnchor.constraint(equalTo: topAnchor, constant: 0).isActive = true

				holder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0).isActive = true

				holder.layer.cornerRadius = 5
				holder.clipsToBounds = true

				holder.widthAnchor.constraint(equalToConstant: 50).isActive = true
				holder.heightAnchor.constraint(equalToConstant: 50).isActive = true

				holder.addSubview(deleteButton)
				deleteButton.centerXAnchor.constraint(equalTo: holder.centerXAnchor).isActive = true
				deleteButton.centerYAnchor.constraint(equalTo: holder.centerYAnchor).isActive = true
				holder.cover(with: deleteButton)

			} else if !isEditing && deleteButton.superview != nil {
				deleteButton.superview?.removeFromSuperview()
				deleteButton.removeFromSuperview()
			}
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		clipsToBounds = true
		layer.cornerRadius = 10
		image.clipsToBounds = true
		image.layer.cornerRadius = 5
		contentView.tintColor = .darkGray
	}

	func setArchivedDropItem(_ newDrop: ArchivedDropItem) {
		archivedDropItem?.delegate = nil
		archivedDropItem = newDrop
		decorate()
	}
	private var archivedDropItem: ArchivedDropItem?

	override func prepareForReuse() {
		archivedDropItem = nil
		decorate()
	}

	private func decorate() {

		image.subviews.forEach { $0.removeFromSuperview() }
		accessoryLabel.text = nil
		accessoryLabelDistance.constant = 0

		if let archivedDropItem = archivedDropItem {

			let info = archivedDropItem.displayInfo
			image.image = info.image
			image.contentMode = info.imageContentMode
			if image.contentMode == .center {
				label.numberOfLines = 9
			} else {
				label.numberOfLines = 2
			}
			label.text = info.title

			if let t = info.accessoryText {
				accessoryLabel.text = t
				accessoryLabelDistance.constant = 8
			}

			if archivedDropItem.isLoading {
				image.isHidden = true
				spinner.startAnimating()
			} else {
				image.isHidden = false
				spinner.stopAnimating()

				// if we're showing an icon, let's try to enahnce things a bit
				if image.contentMode == .center, let backgroundItem = archivedDropItem.backgroundInfoObject {
					if let mapItem = backgroundItem as? MKMapItem {
						let m = MiniMapView(at: mapItem)
						image.cover(with: m)

					} else if let color = backgroundItem as? UIColor {
						image.backgroundColor = color
					}
				}
			}

			archivedDropItem.delegate = self

		} else {
			archivedDropItem?.delegate = nil
			image.image = nil
			image.isHidden = true
			label.text = nil
			spinner.startAnimating()
		}
	}

	func loadCompleted(success: Bool) {
		decorate()
		NSLog("load complete for drop group")
	}
}

