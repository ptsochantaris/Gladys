import UIKit

final class LabelEditorCell: UITableViewCell {
	@IBOutlet weak var labelName: UILabel!
	@IBOutlet weak var tick: UIImageView!

	override func awakeFromNib() {
		super.awakeFromNib()
		if PersistedOptions.darkMode {
			labelName.textColor = .lightGray
		}
	}
}
