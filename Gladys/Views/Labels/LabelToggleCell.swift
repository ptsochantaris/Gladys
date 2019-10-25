//
//  LabelToggleCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 14/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelToggleCell: UITableViewCell {
	@IBOutlet weak var labelCount: UILabel!
	@IBOutlet weak var labelName: UILabel!

	override func setSelected(_ selected: Bool, animated: Bool) {
		accessoryType = selected ? .checkmark : .none
        labelName.textColor = selected ? .darkText : UIColor(named: "colorDarkGray")
	}
}
