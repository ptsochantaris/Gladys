import UIKit

final class LabelEditorCell: UITableViewCell {
    @IBOutlet var labelName: UILabel!
    @IBOutlet var tick: UIImageView!

    override func awakeFromNib() {
        super.awakeFromNib()
        focusEffect = UIFocusHaloEffect()
    }
}
