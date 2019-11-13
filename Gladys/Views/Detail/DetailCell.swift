
import UIKit

final class DetailCell: UITableViewCell {
	@IBOutlet private weak var name: UILabel!
	@IBOutlet private weak var size: UILabel!
	@IBOutlet private weak var desc: UILabel!
	@IBOutlet weak var borderView: UIView!
	@IBOutlet private weak var nameHolder: UIView!
	@IBOutlet weak var inspectButton: UIButton!
	@IBOutlet private weak var viewButton: UIButton!
	@IBOutlet weak var archiveButton: UIButton!
	@IBOutlet private weak var editButton: UIButton!
    @IBOutlet private weak var imageHolder: UIImageView!
    
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

	override func prepareForReuse() {
		super.prepareForReuse()
		inspectionCallback = nil
		viewCallback = nil
		archiveCallback = nil
		editCallback = nil
	}

	override func updateConstraints() {
		inspectButton.isHidden = inspectionCallback == nil
		viewButton.isHidden = viewCallback == nil
		archiveButton.isHidden = archiveCallback == nil
		editButton.isHidden = editCallback == nil
		super.updateConstraints()
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		borderView.layer.cornerRadius = 10
        borderView.layer.shadowColor = UIColor.black.cgColor
        borderView.layer.shadowOffset = CGSize(width: 0, height: 0)
        borderView.layer.shadowOpacity = 0.06
        borderView.layer.shadowRadius = 1.5

        nameHolder.layer.cornerRadius = 5

		inspectButton.accessibilityLabel = "Inspect data"
		viewButton.accessibilityLabel = "Visual item preview"
		archiveButton.accessibilityLabel = "Archive target of link"
		editButton.accessibilityLabel = "Edit item"
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
			let a = UIActivityIndicatorView(style: .medium)
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

    private static let shortFormatter: DateFormatter = {
        let d = DateFormatter()
        d.doesRelativeDateFormatting = true
        d.dateStyle = .short
        d.timeStyle = .short
        return d
    }()

    func configure(with typeEntry: ArchivedDropItemType, showTypeDetails: Bool, darkMode: Bool) -> Bool {
        imageHolder.image = nil

        var hasImage = false
        if let icon = typeEntry.displayIcon, typeEntry.displayIconContentMode == .fill {
            hasImage = true
            icon.desaturated(darkMode: darkMode) { [weak self] img in
                self?.imageHolder.image = img
            }
        }
    
        var ok = true
        
        if let title = typeEntry.displayTitle ?? typeEntry.accessoryTitle ?? typeEntry.encodedUrl?.path {
            name.textAlignment = typeEntry.displayTitleAlignment
            name.text = "\"\(title)\""
            
        } else if typeEntry.dataExists {
            if typeEntry.isWebArchive {
                name.text = DetailCell.shortFormatter.string(from: typeEntry.createdAt)
            } else {
                name.text = hasImage ? nil : "Binary Data"
            }
            name.textAlignment = .center
            
        } else {
            ok = false
            name.text = "Loading Error"
            name.textAlignment = .center
            inspectionCallback = nil
            viewCallback = nil
        }
        
        size.text = typeEntry.sizeDescription
        if showTypeDetails {
            desc.text = typeEntry.typeIdentifier.uppercased()
        } else {
            desc.text = typeEntry.typeDescription.uppercased()
        }
        
        return ok
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
			if !viewButton.isHidden {
				actions.append(UIAccessibilityCustomAction(name: "Show Preview", target: self, selector: #selector(previewSelected)))
			}
			if !editButton.isHidden {
				actions.append(UIAccessibilityCustomAction(name: "Edit Item", target: self, selector: #selector(editSelected(_:))))
			}
			if !archiveButton.isHidden {
				actions.append(UIAccessibilityCustomAction(name: "Archive Link Target", target: self, selector: #selector(archiveSelected(_:))))
			}
			if !inspectButton.isHidden {
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
