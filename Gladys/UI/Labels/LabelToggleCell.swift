import UIKit
import GladysUI

final class LabelToggleCell: UITableViewCell {
    @IBOutlet private var labelCount: UILabel!
    @IBOutlet private var labelName: UILabel!

    weak var parent: LabelSelector?

    var toggle: Filter.Toggle? {
        didSet {
            guard let toggle else { return }
            labelName.text = toggle.function.displayText
            let c = toggle.count
            labelCount.text = c == 1 ? "1 item" : "\(c) items"
        }
    }

    override func setSelected(_ selected: Bool, animated _: Bool) {
        accessoryType = selected ? .checkmark : .none
        labelName.textColor = selected ? .label : .g_colorComponentLabel
    }
}
