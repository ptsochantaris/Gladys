import UIKit

final class LabelListCell: UITableViewCell {
    @IBOutlet var labelName: UILabel!

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            focusEffect = UIFocusHaloEffect()
        }
    }
}
