//
//  ByteCell.swift
//  FEFF
//
//  Created by Paul Tsochantaris on 01/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class ByteCell: UICollectionViewCell {

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
		letter.textColor = .gray
	}

	override var isSelected: Bool {
		didSet {
			if isSelected {
				letter.textColor = .lightGray
				label.textColor = .white
				label.backgroundColor = .darkGray
			} else {
				letter.textColor = .gray
				label.textColor = .darkGray
				label.backgroundColor = .clear
			}
		}
	}
}
