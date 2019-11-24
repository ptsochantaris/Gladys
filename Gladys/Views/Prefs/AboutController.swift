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
    @IBOutlet private weak var unlimitedLabel: UILabel!
    @IBOutlet private weak var versionLabel: UIBarButtonItem!
	@IBOutlet private weak var logo: UIImageView!

	override func viewDidLoad() {
		super.viewDidLoad()

		doneButtonLocation = .right

        unlimitedButton.isHidden = infiniteMode
        unlimitedLabel.isHidden = !infiniteMode

		let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
		let b = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		versionLabel.title = "v\(v) (\(b))"
	}

	@IBAction private func aboutSelected(_ sender: UIButton) {
        guard let u = URL(string: "https://bru.build/app/gladys") else { return }
        UIApplication.shared.connectedScenes.first?.open(u, options: nil) { success in
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
