import UIKit

final class LabelListCell: UITableViewCell {
    @IBOutlet var labelName: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        if #available(iOS 15.0, *) {
            focusEffect = UIFocusHaloEffect()
        }
    }
}
