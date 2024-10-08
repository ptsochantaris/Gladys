import UIKit

final class ByteCell: UICollectionViewCell {
    @IBOutlet private var label: UILabel!
    @IBOutlet private var letter: UILabel!

    var address: Int64 = 0

    override var accessibilityLabel: String? {
        get {
            label.text
        }
        set {}
    }

    override var accessibilityValue: String? {
        get {
            String(format: "Location %X", address)
        }
        set {}
    }

    var byte: UInt8 = 0 {
        didSet {
            label.text = String(format: "%02X", byte)
            letter.text = String(bytes: [byte], encoding: .nonLossyASCII)
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            layer.borderWidth = 0.25
            layer.borderColor = UIColor.separator.cgColor
            isAccessibilityElement = true
            accessibilityHint = "Double-tap and hold then swipe left or right to select a range."
            updateSelected()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        focusEffect = UIFocusHaloEffect(roundedRect: bounds.insetBy(dx: 4, dy: 4), cornerRadius: 0, curve: .circular)
    }

    private func updateSelected() {
        if isSelected {
            label.textColor = .white
            letter.textColor = .white
            label.backgroundColor = UIColor.g_colorTint
        } else {
            label.textColor = UIColor.secondaryLabel
            letter.textColor = UIColor.tertiaryLabel
            label.backgroundColor = .clear
        }
    }

    override var isSelected: Bool {
        didSet {
            updateSelected()
        }
    }
}
