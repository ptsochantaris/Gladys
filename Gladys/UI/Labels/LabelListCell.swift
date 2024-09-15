import UIKit

final class LabelListCell: UITableViewCell {
    @IBOutlet var labelName: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            focusEffect = UIFocusHaloEffect()
        }
    }
}
