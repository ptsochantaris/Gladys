//
//  MessageCell.swift
//  GladysMessage
//
//  Created by Paul Tsochantaris on 03/12/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

let messageCellFormatter: DateFormatter = {
	let d = DateFormatter()
	d.doesRelativeDateFormatting = true
	d.dateStyle = .short
	d.timeStyle = .short
	return d
}()

final class MessageCell: UICollectionViewCell {

	@IBOutlet weak var topLabel: UILabel!
	@IBOutlet weak var bottomLabel: UILabel!
	@IBOutlet weak var imageView: UIImageView!

	override func awakeFromNib() {
		super.awakeFromNib()

		let b = UIView()
		b.backgroundColor = .white
		b.layer.cornerRadius = 10
		b.clipsToBounds = true
		backgroundView = b

		imageView.layer.cornerRadius = 5
		isAccessibilityElement = true
		accessibilityHint = "Select to send"
	}

	var dropItem: ArchivedDropItem? {
		didSet {
			if let dropItem = dropItem {
				topLabel.text = dropItem.oneTitle
				bottomLabel.text = messageCellFormatter.string(from: dropItem.updatedAt)
				imageView.image = dropItem.displayIcon
				switch dropItem.displayMode {
				case .center:
					imageView.contentMode = .center
				case .circle:
					imageView.contentMode = .center
				case .fill:
					imageView.contentMode = .scaleAspectFill
				case .fit:
					imageView.contentMode = .scaleAspectFit
				}
				accessibilityLabel = "Added " + (bottomLabel.text ?? "")
				accessibilityValue = topLabel.text ?? ""
			}
		}
	}
}

