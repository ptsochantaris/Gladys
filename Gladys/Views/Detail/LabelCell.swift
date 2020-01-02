//
//  LabelCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 14/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelCell: UITableViewCell, UIContextMenuInteractionDelegate {
	
	@IBOutlet private weak var labelText: UILabel!
    
    weak var parent: DetailController?

    override func awakeFromNib() {
        super.awakeFromNib()
        let b = UIView()
        b.backgroundColor = UIColor(named: "colorTint")?.withAlphaComponent(0.1)
        selectedBackgroundView = b
        
        let contextMenu = UIContextMenuInteraction(delegate: self)
        addInteraction(contextMenu)
    }
    
    var label: String? {
        didSet {
            labelText.text = label ?? "Add…"
            labelText.textColor = label == nil
                ? selectedBackgroundView?.backgroundColor?.withAlphaComponent(0.8)
                : UIColor(named: "colorComponentLabel")
        }
    }
    
	/////////////////////////////////////

	override var accessibilityValue: String? {
		set {}
		get {
			return labelText.accessibilityValue
		}
	}

	override var accessibilityHint: String? {
		set {}
		get {
			return label == nil ? "Select to add a new label" : "Select to edit"
		}
	}

	override var isAccessibilityElement: Bool {
		set {}
		get {
			return true
		}
	}
        
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let text = self?.label else { return nil }
            
            var children = [
                UIAction(title: "Copy to Clipboard", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = text
                    genericAlert(title: nil, message: "Copied to clipboard", buttonTitle: nil)
                }
            ]
            
            if let p = self?.parent, p.isReadWrite {
                children.append(UIAction(title: "Delete", image: UIImage(systemName: "bin.xmark"), attributes: .destructive) { _ in
                    p.removeLabel(text)
                })
            }
            
            return UIMenu(title: "", image: nil, identifier: nil, options: [], children: children)
        }
    }
}
