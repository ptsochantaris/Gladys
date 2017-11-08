//
//  TodayCell.swift
//  GladysToday
//
//  Created by Paul Tsochantaris on 06/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

let todayCellFormatter: DateFormatter = {
	let d = DateFormatter()
	d.doesRelativeDateFormatting = true
	d.dateStyle = .short
	d.timeStyle = .short
	return d
}()

final class TodayCell: UICollectionViewCell {

	@IBOutlet weak var topLabel: UILabel!
	@IBOutlet weak var bottomLabel: UILabel!
	@IBOutlet weak var imageView: UIImageView!

	override func awakeFromNib() {
		super.awakeFromNib()

		let b = UIView()
		b.backgroundColor = .lightGray
		b.layer.cornerRadius = 10
		backgroundView = b

		let borderView = UIView()
		borderView.backgroundColor = .white
		borderView.layer.cornerRadius = 10
		b.cover(with: borderView, insets: UIEdgeInsetsMake(0, 0, 0.5, 0))

		imageView.layer.cornerRadius = 5
		isAccessibilityElement = true
		accessibilityHint = "Select to copy"
	}

	var dropItem: ArchivedDropItem? {
		didSet {
			if let dropItem = dropItem {
				topLabel.text = dropItem.oneTitle
				bottomLabel.text = todayCellFormatter.string(from: dropItem.updatedAt)
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
