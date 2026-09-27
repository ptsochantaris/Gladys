import UIKit

final class LabelEditorCell: UITableViewCell {
    @IBOutlet var labelName: UILabel!
    @IBOutlet var tick: UIImageView!

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            focusEffect = UIFocusHaloEffect()
        }
    }
}
