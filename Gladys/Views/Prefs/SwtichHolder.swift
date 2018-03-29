//
//  SwtichHolder.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 04/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class SwitchHolder: UIView {

	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		isAccessibilityElement = true
	}

	override var accessibilityLabel: String? {
		set {}
		get {
			let components = subviews
				.sorted { $0.frame.origin.y < $1.frame.origin.y }
				.compactMap { $0 is UILabel ? $0.accessibilityLabel : nil }
			
			return components.count > 0 ? components.joined(separator: ".") : nil
		}
	}

	var switchControl: UISwitch? {
		return subviews.first(where: { $0 is UISwitch }) as? UISwitch
	}

	override var accessibilityValue: String? {
		set {}
		get {
			return switchControl?.accessibilityValue
		}
	}

	override var accessibilityTraits: UIAccessibilityTraits {
		set {}
		get {
			return switchControl?.accessibilityTraits ?? UIAccessibilityTraitNone
		}
	}

	override var accessibilityHint: String? {
		set {}
		get {
			return switchControl?.accessibilityHint
		}
	}

	override func accessibilityActivate() -> Bool {
		switchControl?.isOn = !(switchControl?.isOn ?? false)
		return true
	}
}
