
import UIKit

protocol LoadCompletionDelegate: class {
	func loadCompleted(success: Bool)
}

final class ArchivedDropDisplayInfo {
	var image: UIImage?
	var imageContentMode = UIViewContentMode.center
	var title: String?
}

final class ArchivedItemCell: UICollectionViewCell, LoadCompletionDelegate {
	@IBOutlet weak var image: UIImageView!
	@IBOutlet weak var label: UILabel!
	@IBOutlet var spinner: UIActivityIndicatorView!

	override func awakeFromNib() {
		super.awakeFromNib()
		clipsToBounds = true
		layer.cornerRadius = 10
		image.clipsToBounds = true
		image.layer.cornerRadius = 5
		contentView.tintColor = .darkGray
	}

	func setArchivedDrop(_ newDrop: ArchivedDrop) {
		archivedDrop?.delegate = nil
		archivedDrop = newDrop
		decorate()
	}
	private var archivedDrop: ArchivedDrop?

	override func prepareForReuse() {
		image.image = nil
		image.isHidden = true
		label.text = nil
		spinner.startAnimating()
	}

	private func decorate() {
		if let archivedDrop = archivedDrop {

			let info = archivedDrop.displayInfo
			image.image = info.image
			image.contentMode = info.imageContentMode
			if image.contentMode == .center {
				label.numberOfLines = 10
			} else {
				label.numberOfLines = 2
			}
			label.text = info.title

			if archivedDrop.isLoading {
				image.isHidden = true
				spinner.startAnimating()
			} else {
				image.isHidden = false
				spinner.stopAnimating()
			}

			archivedDrop.delegate = self
		}
	}

	func loadCompleted(success: Bool) {
		decorate()
		NSLog("load complete for drop group")
	}
}

