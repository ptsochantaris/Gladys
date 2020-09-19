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
		get {
			let components = subviews
				.sorted { $0.frame.origin.y < $1.frame.origin.y }
				.compactMap { $0 is UILabel ? $0.accessibilityLabel : nil }
			
            return components.isEmpty ? nil : components.joined(separator: ".")
		}
        set {}
	}

	var switchControl: UISwitch? {
		return subviews.first(where: { $0 is UISwitch }) as? UISwitch
	}

	override var accessibilityValue: String? {
		get {
			return switchControl?.accessibilityValue
		}
        set {}
	}

	override var accessibilityTraits: UIAccessibilityTraits {
		get {
			return switchControl?.accessibilityTraits ?? .none
		}
        set {}
	}

	override var accessibilityHint: String? {
		get {
			return switchControl?.accessibilityHint
		}
        set {}
	}

	override func accessibilityActivate() -> Bool {
		switchControl?.isOn = !(switchControl?.isOn ?? false)
		if let control = switchControl, let target = control.allTargets.first as NSObjectProtocol?, let action = control.actions(forTarget: target, forControlEvent: .valueChanged)?.first {
			target.perform(Selector(action), with: control)
		}
		return true
	}
}
