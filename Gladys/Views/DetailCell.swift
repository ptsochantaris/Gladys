
import UIKit

final class DetailCell: UITableViewCell {
	@IBOutlet weak var type: UILabel!
	@IBOutlet weak var name: UILabel!
	@IBOutlet weak var size: UILabel!
	@IBOutlet weak var borderView: UIView!
	@IBOutlet weak var nameHolder: UIView!

	override func awakeFromNib() {
		super.awakeFromNib()
		borderView.layer.cornerRadius = 10
		nameHolder.layer.cornerRadius = 5
	}
}
