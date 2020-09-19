//
//  LabelCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 14/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelCell: UITableViewCell {
	
	@IBOutlet private weak var labelText: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        let b = UIView()
        b.backgroundColor = UIColor(named: "colorTint")?.withAlphaComponent(0.1)
        selectedBackgroundView = b
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
		get {
			return labelText.accessibilityValue
		}
        set {}
	}

	override var accessibilityHint: String? {
		get {
			return label == nil ? "Select to add a new label" : "Select to edit"
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
