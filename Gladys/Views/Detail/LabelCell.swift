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

	override func tintColorDidChange() {
		labelText.tintColor = tintColor
		let t = tintColor.withAlphaComponent(0.6)
		labelText.highlightedTextColor = t
	}

	var label: String? {
		didSet {
			if let l = label {
				labelText.text = l
				labelText.isHighlighted = false
			} else {
				labelText.text = "Add Label"
				labelText.isHighlighted = true
			}
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
			return labelText.isHighlighted ? "Select to add a new label" : "Select to edit"
		}
	}

	override var isAccessibilityElement: Bool {
		set {}
		get {
			return true
		}
	}
}
