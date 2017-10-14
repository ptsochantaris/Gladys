
import UIKit

final class DetailCell: UITableViewCell {
	@IBOutlet weak var type: UILabel!
	@IBOutlet weak var name: UILabel!
	@IBOutlet weak var size: UILabel!
	@IBOutlet weak var borderView: UIView!
	@IBOutlet weak var nameHolder: UIView!
	@IBOutlet weak var inspectButton: UIButton!

	var selectionCallback: (()->Void)? {
		didSet {
			if inspectButton != nil {
				inspectButton.alpha = (selectionCallback != nil) ? 0.7 : 0
			}
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		borderView.layer.cornerRadius = 10
		nameHolder.layer.cornerRadius = 5

		let b = UIView()
		b.translatesAutoresizingMaskIntoConstraints = false
		b.backgroundColor = .lightGray
		b.layer.cornerRadius = 10
		contentView.insertSubview(b, belowSubview: borderView)
		[
			b.topAnchor.constraint(equalTo: borderView.topAnchor),
			b.leadingAnchor.constraint(equalTo: borderView.leadingAnchor),
			b.trailingAnchor.constraint(equalTo: borderView.trailingAnchor),
			b.bottomAnchor.constraint(equalTo: borderView.bottomAnchor, constant: 0.5)
		].forEach { $0.isActive = true }
	}

	override func dragStateDidChange(_ dragState: UITableViewCellDragState) {
		super.dragStateDidChange(dragState)
		inspectButton.alpha = (selectionCallback != nil && dragState == .none) ? 0.7 : 0
	}

	@IBAction func inspectSelected(_ sender: UIButton) {
		selectionCallback?()
	}

}
