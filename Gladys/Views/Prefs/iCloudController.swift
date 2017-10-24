//
//  iCloudController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 24/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class iCloudController: GladysViewController {

	@IBOutlet weak var icloudLabel: UILabel!
	@IBOutlet weak var icloudSwitch: UISwitch!
	@IBOutlet weak var icloudSpinner: UIActivityIndicatorView!
	@IBOutlet weak var updateNowButton: UIButton!
	// TODO: accessibility

	@IBAction func updateNowSelected(_ sender: UIButton) {
		CloudManager.sync { [weak self] changes, error in
			guard let s = self else { return }
			if let error = error {
				genericAlert(title: "Sync Error", message: error.localizedDescription, on: s)
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		NotificationCenter.default.addObserver(self, selector: #selector(icloudTransitionChanged), name: .CloudManagerStatusChanged, object: nil)

		icloudSwitch.isOn = CloudManager.syncSwitchedOn
		icloudSwitch.addTarget(self, action: #selector(icloudSwitchChanged), for: .valueChanged)
		icloudSwitch.tintColor = UIColor.lightGray
		icloudSwitch.onTintColor = view.tintColor
		updateiCloudControls()
	}

	@objc private func icloudTransitionChanged() {
		updateiCloudControls()
		UIView.animate(animations: {
			self.view.layoutIfNeeded()
		}, completion: nil)
	}

	private func updateiCloudControls() {
		updateNowButton.isHidden = !CloudManager.syncSwitchedOn
		if CloudManager.syncTransitioning {
			icloudSwitch.isEnabled = false
			icloudLabel.text = CloudManager.syncSwitchedOn ? "Deactinvating" : "Activating"
			icloudSpinner.startAnimating()
		} else if CloudManager.syncing {
			icloudSwitch.isEnabled = false
			updateNowButton.isEnabled = false
			icloudLabel.text = "Updating Data"
			icloudSpinner.startAnimating()
		} else {
			icloudSwitch.isEnabled = true
			updateNowButton.isEnabled = true
			icloudLabel.text = "iCloud Sync"
			icloudSpinner.stopAnimating()
			icloudSwitch.isOn = CloudManager.syncSwitchedOn
		}
	}

	@objc private func icloudSwitchChanged() {
		if icloudSpinner.isAnimating { return }

		if icloudSwitch.isOn {
			CloudManager.activate { error in
				DispatchQueue.main.async {
					if let error = error {
						genericAlert(title: "Could not change state", message: error.localizedDescription, on: self)
					}
				}
			}
		} else {
			CloudManager.deactivate { error in
				DispatchQueue.main.async {
					if let error = error {
						genericAlert(title: "Could not change state", message: error.localizedDescription, on: self)
					}
				}
			}
		}
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
