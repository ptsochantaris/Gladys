//
//  AboutController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 05/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import StoreKit

final class AboutController: UIViewController {

	@IBOutlet weak var unlimitedButton: UIButton!

	override func viewDidLoad() {
		super.viewDidLoad()
		unlimitedButton.isHidden = infiniteMode
	}

	@IBAction func aboutSelected(_ sender: UIButton) {
		let u = URL(string: "https://bru.build/app/gladys")!
		UIApplication.shared.open(u, options: [:]) { success in
			if success {
				self.done()
			}
		}
	}

	@IBAction func doneSelected(_ sender: UIBarButtonItem) {
		done()
	}

	private func done() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
		}
		dismiss(animated: true)
	}

	@IBAction func unlimitedSelected(_ sender: UIButton) {
		done()
		ViewController.shared.displayIAPRequest(newTotal: -1)
	}
}
