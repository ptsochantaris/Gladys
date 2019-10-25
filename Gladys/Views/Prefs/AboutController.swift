//
//  AboutController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 05/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import StoreKit

final class AboutController: GladysViewController {

	@IBOutlet private weak var unlimitedButton: UIButton!
	@IBOutlet private weak var unlimitedSpacing: NSLayoutConstraint!
	@IBOutlet private weak var webSiteSpacing: NSLayoutConstraint!
	@IBOutlet private weak var versionLabel: UIBarButtonItem!
	@IBOutlet private weak var logo: UIImageView!

	@IBOutlet private var subtitleLabels: [UILabel]!

	override func viewDidLoad() {
		super.viewDidLoad()

		doneLocation = .right

		if infiniteMode {
			unlimitedButton.isHidden = true
			unlimitedSpacing.constant = 0
			webSiteSpacing.constant = 0
		}

		let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
		let b = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		versionLabel.title = "v\(v) (\(b))"
	}

	@IBAction private func aboutSelected(_ sender: UIButton) {
		let u = URL(string: "https://bru.build/app/gladys")!
		UIApplication.shared.open(u, options: [:]) { success in
			if success {
				self.done()
			}
		}
	}

	@IBAction private func unlimitedSelected(_ sender: UIButton) {
		done()
		IAPManager.shared.displayRequest(newTotal: -1)
	}
}
