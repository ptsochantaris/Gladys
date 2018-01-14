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

		let backgroundEffect = UIVisualEffectView(effect: UIBlurEffect(style: .light))
		backgroundEffect.layer.cornerRadius = 10
		backgroundEffect.clipsToBounds = true
		backgroundView = backgroundEffect

		let imageEffect = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
		imageEffect.layer.cornerRadius = 5
		imageEffect.clipsToBounds = true
		imageView.coverUnder(with: imageEffect)

		imageView.layer.cornerRadius = 5
		isAccessibilityElement = true
		accessibilityHint = "Select to copy"
	}

	var dropItem: ArchivedDropItem? {
		didSet {
			if let dropItem = dropItem {
				topLabel.text = dropItem.displayText.0
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
