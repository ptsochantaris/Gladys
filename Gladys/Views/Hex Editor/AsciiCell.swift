//
//  AsciiCell.swift
//  FEFF
//
//  Created by Paul Tsochantaris on 04/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class AsciiCell: UICollectionViewCell {

	@IBOutlet private weak var label: UILabel!
	@IBOutlet private weak var letter: UILabel!

	var address: Int64 = 0

	override var accessibilityLabel: String? {
		set {}
		get {
			return letter.text
		}
	}

	override var accessibilityValue: String? {
		set {}
		get {
			return String(format: "Location %X", address)
		}
	}

	var byte: UInt8 = 0 {
		didSet {
			label.text = String(format: "%02X", byte)
			let t = String(bytes: [byte], encoding: .nonLossyASCII)
			letter.text = t
			accessibilityValue = t
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		layer.borderWidth = 0.25
        layer.borderColor = UIColor.separator.cgColor
		isAccessibilityElement = true
        accessibilityHint = "Double-tap and hold then swipe left or right to select a range."
		updateSelected()
	}

	private func updateSelected() {
		if isSelected {
            letter.textColor = .white
			label.textColor = .white
			letter.backgroundColor = UIColor(named: "colorTint")
		} else {
            letter.textColor = UIColor.secondaryLabel
            label.textColor = UIColor.tertiaryLabel
			letter.backgroundColor = .clear
		}
	}

	override var isSelected: Bool {
		didSet {
			updateSelected()
		}
	}
}
