//
//  LabelEditorCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 19/12/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelEditorCell: UITableViewCell {
    @IBOutlet var labelName: UILabel!
    @IBOutlet var tick: UIImageView!

    override func awakeFromNib() {
        super.awakeFromNib()
        if #available(iOS 15.0, *) {
            focusEffect = UIFocusHaloEffect()
        }
    }
}
