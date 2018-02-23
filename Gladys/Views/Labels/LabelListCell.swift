//
//  LabelListCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 15/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelListCell: UITableViewCell {
	@IBOutlet weak var labelName: UILabel!

	override func awakeFromNib() {
		super.awakeFromNib()
		if PersistedOptions.darkMode {
			labelName.textColor = .lightGray
		}
	}
}

