import UIKit

final class LabelCell: UITableViewCell {
    @IBOutlet private var labelText: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        let b = UIView()
        b.backgroundColor = UIColor.g_colorTint.withAlphaComponent(0.1)
        selectedBackgroundView = b

        if #available(iOS 15.0, *) {
            self.focusEffect = UIFocusHaloEffect()
        }
    }

    var label: String? {
        didSet {
            labelText.text = label ?? "Add…"
            labelText.textColor = label == nil
                ? selectedBackgroundView?.backgroundColor?.withAlphaComponent(0.8)
                : .g_colorComponentLabel
        }
    }

    /////////////////////////////////////

    override var accessibilityValue: String? {
        get {
            labelText.accessibilityValue
        }
        set {}
    }

    override var accessibilityHint: String? {
        get {
            label == nil ? "Select to add a new label" : "Select to edit"
        }
        set {}
    }

    override var isAccessibilityElement: Bool {
        get {
            true
        }
        set {}
    }
}
