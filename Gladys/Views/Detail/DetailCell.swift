
import UIKit

final class DetailCell: UITableViewCell {
	@IBOutlet weak var type: UILabel!
	@IBOutlet weak var name: UILabel!
	@IBOutlet weak var size: UILabel!
	@IBOutlet weak var borderView: UIView!
	@IBOutlet weak var nameHolder: UIView!
	@IBOutlet weak var inspectButton: UIButton!
	@IBOutlet weak var viewButton: UIButton!
	@IBOutlet weak var labelRightConstraint: NSLayoutConstraint!
	@IBOutlet weak var labelLeftConstraint: NSLayoutConstraint!

	var inspectionCallback: (()->Void)? {
		didSet {
			if inspectButton != nil {
				inspectButton.alpha = (inspectionCallback != nil) ? 0.7 : 0
			}
		}
	}

	var viewCallback: (()->Void)? {
		didSet {
			if viewButton != nil {
				viewButton.alpha = (viewCallback != nil) ? 0.7 : 0
			}
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		borderView.layer.cornerRadius = 10
		nameHolder.layer.cornerRadius = 5

		inspectButton.accessibilityLabel = "Inspect raw data"
		viewButton.accessibilityLabel = "Visual item preview"

		let b = UIView()
		b.translatesAutoresizingMaskIntoConstraints = false
		b.backgroundColor = .lightGray
		b.layer.cornerRadius = 10
		contentView.insertSubview(b, belowSubview: borderView)
		[
			b.topAnchor.constraint(equalTo: borderView.topAnchor),
			b.leadingAnchor.constraint(equalTo: borderView.leadingAnchor),
			b.trailingAnchor.constraint(equalTo: borderView.trailingAnchor),
			b.bottomAnchor.constraint(equalTo: borderView.bottomAnchor, constant: 0.5)
		].forEach { $0.isActive = true }
	}

	override func dragStateDidChange(_ dragState: UITableViewCellDragState) {
		super.dragStateDidChange(dragState)
		inspectButton.alpha = (inspectionCallback != nil && dragState == .none) ? 0.7 : 0
		viewButton.alpha = (viewCallback != nil && dragState == .none) ? 0.7 : 0
	}

	@IBAction func inspectSelected(_ sender: UIButton) {
		inspectionCallback?()
	}

	@IBAction func viewSelected(_ sender: UIButton) {
		viewCallback?()
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		labelLeftConstraint.constant = viewCallback != nil ? 24 : 0
		labelRightConstraint.constant = inspectionCallback != nil ? 24 : 0
	}

	/////////////////////////////////////

	override var accessibilityLabel: String? {
		set {}
		get {
			return type.text
		}
	}

	override var accessibilityValue: String? {
		set {}
		get {
			if name.text == "Binary Data" {
				return "\(size.text ?? ""), Binary data"
			} else {
				return "\(size.text ?? ""), Contents: \(name.text ?? "")"
			}
		}
	}

	override var accessibilityHint: String? {
		set {}
		get {
			return inspectButton.alpha == 0 ? nil : "Select to inspect"
		}
	}

	override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
		set {}
		get {
			return [UIAccessibilityCustomAction(name: "Show Preview", target: self, selector: #selector(previewSelected))]
		}
	}

	@objc private func previewSelected() {
		viewCallback?()
	}

	override func accessibilityActivate() -> Bool {
		if inspectButton.alpha != 0 {
			inspectSelected(inspectButton)
		}
		return true
	}

	override var accessibilityTraits: UIAccessibilityTraits {
		get {
			if inspectButton.alpha == 0 {
				return UIAccessibilityTraitStaticText
			} else {
				return UIAccessibilityTraitButton
			}
		}
		set {}
	}

	override var isAccessibilityElement: Bool {
		set {}
		get {
			return true
		}
	}
}
