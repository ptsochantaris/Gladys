import UIKit

protocol DetailCellDelegate: AnyObject {
    func inspectOptionSelected(in cell: DetailCell)
    func archiveOptionSelected(in cell: DetailCell)
    func viewOptionSelected(in cell: DetailCell)
    func editOptionSelected(in cell: DetailCell)
}

final class DetailCell: UITableViewCell {
    
    struct Flags: OptionSet {
        let rawValue: UInt8

        static let inspection = Flags(rawValue: 1 << 0)
        static let archive    = Flags(rawValue: 1 << 1)
        static let view       = Flags(rawValue: 1 << 2)
        static let edit       = Flags(rawValue: 1 << 3)
    }
    
	@IBOutlet private var name: UILabel!
	@IBOutlet private var size: UILabel!
	@IBOutlet private var desc: UILabel!
	@IBOutlet var inspectButton: UIButton!
	@IBOutlet private var viewButton: UIButton!
	@IBOutlet var archiveButton: UIButton!
	@IBOutlet private var editButton: UIButton!
    @IBOutlet private var imageHolder: UIImageView!

    private var buttonFlags = Flags()
    
    weak var delegate: DetailCellDelegate?

	override func updateConstraints() {
        inspectButton.isHidden = !buttonFlags.contains(.inspection)
		archiveButton.isHidden = !buttonFlags.contains(.archive)
        viewButton.isHidden = !buttonFlags.contains(.view)
		editButton.isHidden = !buttonFlags.contains(.edit)
		super.updateConstraints()
	}

	override func awakeFromNib() {
		super.awakeFromNib()

		inspectButton.accessibilityLabel = "Inspect data"
        archiveButton.accessibilityLabel = "Archive target of link"
		viewButton.accessibilityLabel = "Visual item preview"
		editButton.accessibilityLabel = "Edit item"
	}

	override func dragStateDidChange(_ dragState: UITableViewCell.DragState) {
		super.dragStateDidChange(dragState)
		inspectButton.alpha = (buttonFlags.contains(.inspection) && dragState == .none) ? 0.7 : 0
        archiveButton.alpha = (buttonFlags.contains(.archive) && dragState == .none) ? 0.7 : 0
		viewButton.alpha = (buttonFlags.contains(.view) && dragState == .none) ? 0.7 : 0
		editButton.alpha = (buttonFlags.contains(.edit) && dragState == .none) ? 0.7 : 0
	}

	@objc private func previewSelected() {
        delegate?.viewOptionSelected(in: self)
	}

	@IBAction private func editSelected(_ sender: UIButton) {
        delegate?.editOptionSelected(in: self)
	}

	@IBAction private func inspectSelected(_ sender: UIButton) {
        delegate?.inspectOptionSelected(in: self)
	}

	@IBAction private func archiveSelected(_ sender: UIButton) {
		UIAccessibility.post(notification: .announcement, argument: "Archiving, please wait")
        delegate?.archiveOptionSelected(in: self)
	}

	@IBAction private func viewSelected(_ sender: UIButton) {
        delegate?.viewOptionSelected(in: self)
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
    
    func configure(with component: Component, showTypeDetails: Bool, isReadWrite: Bool, delegate: DetailCellDelegate) {
        self.delegate = delegate

        imageHolder.image = nil

        var hasImage = false
        if component.displayIconContentMode == .fill, let icon = component.componentIcon {
            hasImage = true
            let darkMode = traitCollection.containsTraits(in: UITraitCollection(userInterfaceStyle: .dark))
            icon.desaturated(darkMode: darkMode) { [weak self] img in
                self?.imageHolder.image = img
            }
        }
    
        var ok = true
        let itemURL = component.encodedUrl
        
        if let title = component.displayTitle ?? component.accessoryTitle ?? itemURL?.path {
            name.textAlignment = component.displayTitleAlignment
            name.text = "\"\(title)\""
            
        } else if component.dataExists {
            if component.isWebArchive {
                name.text = DetailCell.shortFormatter.string(from: component.createdAt)
            } else {
                name.text = hasImage ? nil : "Binary Data"
            }
            name.textAlignment = .center
            
        } else {
            ok = false
            name.text = "Loading Error"
            name.textAlignment = .center
        }
        
        size.text = component.sizeDescription
        
        if showTypeDetails {
            desc.text = component.typeIdentifier.uppercased()
        } else {
            desc.text = component.typeDescription.uppercased()
        }
        
        var newFlags = Flags()
        if ok {
            newFlags.insert(.inspection)
            
            if isReadWrite {
                if let i = itemURL, let s = i.scheme, s.hasPrefix("http") {
                    newFlags.insert(.archive)
                }

                if itemURL != nil || component.isText {
                    newFlags.insert(.edit)
                }
            }

            if component.canPreview {
                newFlags.insert(.view)
            }
        }
        buttonFlags = newFlags
        setNeedsUpdateConstraints()
    }
    
	/////////////////////////////////////

	override var accessibilityLabel: String? {
		get {
			return desc.text
		}
        set {}
	}

	override var accessibilityValue: String? {
		get {
			if name.text == "Binary Data" {
				return "\(size.text ?? ""), Binary data"
			} else {
				return "\(size.text ?? ""), Contents: \(name.text ?? "")"
			}
		}
        set {}
	}

	override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
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
        set {}
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
		get {
			return true
		}
        set {}
	}
}
