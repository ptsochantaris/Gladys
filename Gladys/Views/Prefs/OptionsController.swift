//
//  OptionsController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 04/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class OptionsController: GladysViewController {

	@IBOutlet weak var separateItemsSwitch: UISwitch!
	@IBOutlet weak var twoColumnsSwitch: UISwitch!

	@IBAction func twoColumnsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.forceTwoColumnPreference = sender.isOn
		ViewController.shared.forceLayout()
	}

	@IBAction func separateItemsSwitchSelected(_ sender: UISwitch) {
		PersistedOptions.separateItemPreference = sender.isOn
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		separateItemsSwitch.tintColor = UIColor.lightGray
		separateItemsSwitch.onTintColor = view.tintColor
		separateItemsSwitch.isOn = PersistedOptions.separateItemPreference

		twoColumnsSwitch.tintColor = UIColor.lightGray
		twoColumnsSwitch.onTintColor = view.tintColor
		twoColumnsSwitch.isOn = PersistedOptions.forceTwoColumnPreference
	}

	private func done() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
		}
		dismiss(animated: true)
	}

	@IBAction func doneSelected(_ sender: UIBarButtonItem) {
		done()
	}
}
