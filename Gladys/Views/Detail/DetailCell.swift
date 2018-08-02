
import UIKit

final class DetailCell: UITableViewCell {
	@IBOutlet weak var name: UILabel!
	@IBOutlet weak var size: UILabel!
	@IBOutlet weak var desc: UILabel!

	@IBOutlet weak var borderView: UIView!
	@IBOutlet private weak var nameHolder: UIView!

	@IBOutlet private weak var inspectButton: UIButton!
	@IBOutlet private weak var viewButton: UIButton!
	@IBOutlet private weak var archiveButton: UIButton!
	@IBOutlet private weak var editButton: UIButton!

	@IBOutlet private weak var editHeight: NSLayoutConstraint!
	@IBOutlet private weak var inspectHeight: NSLayoutConstraint!
	@IBOutlet private weak var archiveHeight: NSLayoutConstraint!
	@IBOutlet private weak var viewHeight: NSLayoutConstraint!

	var inspectionCallback: (()->Void)? {
		didSet {
			setNeedsUpdateConstraints()
		}
	}

	var viewCallback: (()->Void)? {
		didSet {
			setNeedsUpdateConstraints()
		}
	}

	var archiveCallback: (()->Void)? {
		didSet {
			setNeedsUpdateConstraints()
		}
	}

	var editCallback: (()->Void)? {
		didSet {
			setNeedsUpdateConstraints()
		}
	}

	override func updateConstraints() {
		super.updateConstraints()
		editHeight.constant = editCallback == nil ? 0 : 44
		archiveHeight.constant = archiveCallback == nil ? 0 : 44
		viewHeight.constant = viewCallback == nil ? 0 : 44
		inspectHeight.constant = inspectionCallback == nil ? 0 : 44
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		borderView.layer.cornerRadius = 10
		nameHolder.layer.cornerRadius = 5

		inspectButton.accessibilityLabel = "Inspect raw data"
		viewButton.accessibilityLabel = "Visual item preview"
		archiveButton.accessibilityLabel = "Archive target of link"
		editButton.accessibilityLabel = "Edit item"

		let b = UIView()
		b.translatesAutoresizingMaskIntoConstraints = false
		b.backgroundColor = .lightGray
		b.layer.cornerRadius = 10
		contentView.insertSubview(b, belowSubview: borderView)
		NSLayoutConstraint.activate([
			b.topAnchor.constraint(equalTo: borderView.topAnchor),
			b.leadingAnchor.constraint(equalTo: borderView.leadingAnchor),
			b.trailingAnchor.constraint(equalTo: borderView.trailingAnchor),
			b.bottomAnchor.constraint(equalTo: borderView.bottomAnchor, constant: 0.5)
		])

		if PersistedOptions.darkMode {
			borderView.backgroundColor = .darkGray
			b.backgroundColor = ViewController.darkColor
			nameHolder.backgroundColor = #colorLiteral(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
			name.textColor = ViewController.tintColor
			desc.textColor = .lightGray
		}
	}

	override func dragStateDidChange(_ dragState: UITableViewCell.DragState) {
		super.dragStateDidChange(dragState)
		inspectButton.alpha = (inspectionCallback != nil && dragState == .none) ? 0.7 : 0
		viewButton.alpha = (viewCallback != nil && dragState == .none) ? 0.7 : 0
		archiveButton.alpha = (viewCallback != nil && dragState == .none) ? 0.7 : 0
		editButton.alpha = (editCallback != nil && dragState == .none) ? 0.7 : 0
	}

	@objc private func previewSelected() {
		viewCallback?()
	}

	@IBAction private func editSelected(_ sender: UIButton) {
		editCallback?()
	}

	@IBAction private func inspectSelected(_ sender: UIButton) {
		inspectionCallback?()
	}

	@IBAction private func archiveSelected(_ sender: UIButton) {
		UIAccessibility.post(notification: .announcement, argument: "Archiving, please wait")
		archiveCallback?()
	}

	@IBAction private func viewSelected(_ sender: UIButton) {
		viewCallback?()
	}

	func animateArchive(_ animate: Bool) {
		let existingSpinner = contentView.viewWithTag(72634) as? UIActivityIndicatorView
		if animate, existingSpinner == nil {
			let a = UIActivityIndicatorView(style: .gray)
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
			UIAccessibility.post(notification: .layoutChanged, argument: nil)
		}
	}

	/////////////////////////////////////

	override var accessibilityLabel: String? {
		set {}
		get {
			return desc.text
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

	override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
		set {}
		get {
			var actions = [UIAccessibilityCustomAction]()
			if viewHeight.constant > 0 {
				actions.append(UIAccessibilityCustomAction(name: "Show Preview", target: self, selector: #selector(previewSelected)))
			}
			if editHeight.constant > 0 {
				actions.append(UIAccessibilityCustomAction(name: "Edit Item", target: self, selector: #selector(editSelected(_:))))
			}
			if archiveHeight.constant > 0 {
				actions.append(UIAccessibilityCustomAction(name: "Archive Link Target", target: self, selector: #selector(archiveSelected(_:))))
			}
			if inspectHeight.constant > 0 {
				actions.append(UIAccessibilityCustomAction(name: "Inspect Item", target: self, selector: #selector(inspectSelected(_:))))
			}
			return actions
		}
	}

	override func accessibilityActivate() -> Bool {
		return true
	}

	override var accessibilityTraits: UIAccessibilityTraits {
		get {
			if inspectButton.alpha == 0 {
				return .staticText
			} else {
				return .button
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
