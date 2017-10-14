//
//  LabelCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 14/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelCell: UITableViewCell {
	
	@IBOutlet var labelHolder: UIView!
	@IBOutlet var labelText: UILabel!

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

	override func awakeFromNib() {
		super.awakeFromNib()
		labelHolder.layer.cornerRadius = 15
	}

	override func setHighlighted(_ highlighted: Bool, animated: Bool) {
		strongMode(highlighted)
	}

	override func setSelected(_ selected: Bool, animated: Bool) {
		strongMode(selected)
	}

	private func strongMode(_ on: Bool) {
		labelHolder.layer.borderColor = (labelText.isHighlighted ? labelText.highlightedTextColor : labelText.textColor)?.cgColor
		labelHolder.layer.borderWidth = on ? 0.5 :  0
	}
}
