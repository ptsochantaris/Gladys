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

	var byte: UInt8 = 0 {
		didSet {
			label.text = String(format: "%02X", byte)
			letter.text = String(bytes: [byte], encoding: .nonLossyASCII)
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		layer.borderWidth = 0.25
		layer.borderColor = UIColor.lightGray.cgColor
		label.textColor = .gray
	}

	override var isSelected: Bool {
		didSet {
			if isSelected {
				label.textColor = backgroundColor
				letter.textColor = backgroundColor
				letter.backgroundColor = .darkGray
				layer.borderColor = backgroundColor?.cgColor
			} else {
				label.textColor = .gray
				letter.textColor = .darkGray
				letter.backgroundColor = backgroundColor
				layer.borderColor = UIColor.lightGray.cgColor
			}
		}
	}
}
