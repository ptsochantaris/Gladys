//
//  AsciiCell.swift
//  FEFF
//
//  Created by Paul Tsochantaris on 04/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class AsciiCell: UICollectionViewCell {

	@IBOutlet weak var label: UILabel!
	@IBOutlet weak var letter: UILabel!

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
		layer.borderColor = UIColor.lightGray.cgColor
		label.textColor = .gray
		isAccessibilityElement = true
	}

	override var isSelected: Bool {
		didSet {
			if isSelected {
				label.textColor = .lightGray
				letter.textColor = .white
				letter.backgroundColor = .darkGray
			} else {
				label.textColor = .gray
				letter.textColor = .darkGray
				letter.backgroundColor = .clear
			}
		}
	}
}
