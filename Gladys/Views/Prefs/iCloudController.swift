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
	@IBOutlet weak var limitToWiFiSwitch: UISwitch!
	// TODO: accessibility

	@IBAction func limitToWiFiChanged(_ sender: UISwitch) {
		CloudManager.onlySyncOverWiFi = sender.isOn
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		limitToWiFiSwitch.isOn = CloudManager.onlySyncOverWiFi

		NotificationCenter.default.addObserver(self, selector: #selector(icloudTransitionChanged), name: .CloudManagerStatusChanged, object: nil)

		icloudSwitch.isOn = CloudManager.syncSwitchedOn
		icloudSwitch.addTarget(self, action: #selector(icloudSwitchChanged), for: .valueChanged)

		icloudSwitch.tintColor = UIColor.lightGray
		icloudSwitch.onTintColor = view.tintColor

		limitToWiFiSwitch.tintColor = UIColor.lightGray
		limitToWiFiSwitch.onTintColor = view.tintColor

		updateiCloudControls()
	}

	@objc private func icloudTransitionChanged() {
		updateiCloudControls()
		UIView.animate(animations: {
			self.view.layoutIfNeeded()
		}, completion: nil)
	}

	private func updateiCloudControls() {
		if CloudManager.syncTransitioning {
			icloudSwitch.isEnabled = false
			if CloudManager.syncing {
				icloudLabel.text = "Syncing"
			} else {
				icloudLabel.text = CloudManager.syncSwitchedOn ? "Deactinvating" : "Activating"
			}
			icloudSpinner.startAnimating()
		} else if CloudManager.syncing {
			icloudSwitch.isEnabled = false
			icloudLabel.text = "Syncing"
			icloudSpinner.startAnimating()
		} else {
			icloudSwitch.isEnabled = true
			icloudLabel.text = "iCloud Sync"
			icloudSpinner.stopAnimating()
			icloudSwitch.isOn = CloudManager.syncSwitchedOn
		}
	}

	@objc private func icloudSwitchChanged() {
		if icloudSpinner.isAnimating { return }

		if icloudSwitch.isOn && !CloudManager.syncSwitchedOn {
			if model.drops.count > 0 {
				let contentSize = diskSizeFormatter.string(fromByteCount: model.sizeInBytes)
				let message = "If you have previously synced Gladys items they will merge with existing items.\n\nThis may upload up to \(contentSize) of data.\n\nIs it OK to proceed?"
				let a = UIAlertController(title: "Upload Existing Items?", message: message, preferredStyle: .alert)
				a.addAction(UIAlertAction(title: "Proceed", style: .default, handler: { action in
					self.proceedWithActivation()
				}))
				a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in
					self.icloudSwitch.setOn(false, animated: true)
				}))
				present(a, animated: true)
			} else {
				proceedWithActivation()
			}
		} else if CloudManager.syncSwitchedOn {
			CloudManager.deactivate(force: false) { error in
				DispatchQueue.main.async {
					if let error = error {
						genericAlert(title: "Could not change state", message: error.localizedDescription, on: self)
					}
				}
			}
		}
	}

	private func proceedWithActivation() {
		CloudManager.activate { error in
			DispatchQueue.main.async {
				if let error = error {
					genericAlert(title: "Could not change state", message: error.localizedDescription, on: self)
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
