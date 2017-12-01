
import UIKit

final class DetailCell: UITableViewCell {
	@IBOutlet weak var type: UILabel!
	@IBOutlet weak var name: UILabel!
	@IBOutlet weak var size: UILabel!
	@IBOutlet weak var borderView: UIView!
	@IBOutlet weak var nameHolder: UIView!

	@IBOutlet weak var inspectButton: UIButton!
	@IBOutlet weak var viewButton: UIButton!
	@IBOutlet weak var archiveButton: UIButton!

	@IBOutlet weak var inspectWidth: NSLayoutConstraint!
	@IBOutlet weak var viewWidth: NSLayoutConstraint!
	@IBOutlet weak var archiveWidth: NSLayoutConstraint!

	var inspectionCallback: (()->Void)? {
		didSet {
			if inspectButton != nil {
				let showButton = inspectionCallback != nil
				inspectWidth.constant = showButton ? 44 : 0
			}
		}
	}

	var viewCallback: (()->Void)? {
		didSet {
			if viewButton != nil {
				let showButton = viewCallback != nil
				viewWidth.constant = showButton ? 44 : 0
			}
		}
	}

	var archiveCallback: (()->Void)? {
		didSet {
			if archiveButton != nil {
				let showButton = archiveCallback != nil
				archiveWidth.constant = showButton ? 44 : 0
			}
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		borderView.layer.cornerRadius = 10
		nameHolder.layer.cornerRadius = 5

		inspectButton.accessibilityLabel = "Inspect raw data"
		viewButton.accessibilityLabel = "Visual item preview"
		archiveButton.accessibilityLabel = "Archive target of link"

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

	@IBAction func archiveSelected(_ sender: UIButton) {
		archiveCallback?()
	}

	@IBAction func viewSelected(_ sender: UIButton) {
		viewCallback?()
	}

	func animateArchive(_ animate: Bool) {
		let existingSpinner = contentView.viewWithTag(72634) as? UIActivityIndicatorView
		if animate, existingSpinner == nil {
			let a = UIActivityIndicatorView(activityIndicatorStyle: .gray)
			a.tag = 72634
			a.color = tintColor
			a.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(a)
			NSLayoutConstraint.activate([
				a.centerXAnchor.constraint(equalTo: archiveButton.centerXAnchor),
				a.centerYAnchor.constraint(equalTo: archiveButton.centerYAnchor)
			])
			a.startAnimating()
			archiveButton.alpha = 0
		} else if !animate, let e = existingSpinner {
			e.stopAnimating()
			e.removeFromSuperview()
			archiveButton.alpha = 1
		}
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
