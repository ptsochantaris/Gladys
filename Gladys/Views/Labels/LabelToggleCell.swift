//
//  LabelToggleCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 14/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelToggleCell: UITableViewCell {
	@IBOutlet private var labelCount: UILabel!
	@IBOutlet private var labelName: UILabel!
    
    weak var parent: LabelSelector?
        
    var toggle: Filter.Toggle? {
        didSet {
            guard let toggle = toggle else { return }
            labelName.text = toggle.function.displayText
            let c = toggle.count
            labelCount.text = c == 1 ? "1 item" : "\(c) items"
        }
    }

	override func setSelected(_ selected: Bool, animated: Bool) {
		accessoryType = selected ? .checkmark : .none
        labelName.textColor = selected ? .label : .g_colorComponentLabel
	}    
}
