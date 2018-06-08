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
	@IBOutlet weak var eraseAlliCloudData: UIButton!
	@IBOutlet weak var actionUploadSwitch: UISwitch!
	@IBOutlet weak var syncNowButton: UIBarButtonItem!

	@IBOutlet var headerLabels: [UILabel]!
	@IBOutlet var subtitleLabels: [UILabel]!

	@IBAction func limitToWiFiChanged(_ sender: UISwitch) {
		CloudManager.onlySyncOverWiFi = sender.isOn
	}

	@IBAction func uploadItemsFromShareChanged(_ sender: UISwitch) {
		CloudManager.shareActionShouldUpload = sender.isOn
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		doneLocation = .right

		NotificationCenter.default.addObserver(self, selector: #selector(icloudTransitionChanged), name: .CloudManagerStatusChanged, object: nil)

		icloudSwitch.isOn = CloudManager.syncSwitchedOn
		icloudSwitch.tintColor = .lightGray
		icloudSwitch.addTarget(self, action: #selector(icloudSwitchChanged), for: .valueChanged)

		limitToWiFiSwitch.isOn = CloudManager.onlySyncOverWiFi
		limitToWiFiSwitch.tintColor = .lightGray

		actionUploadSwitch.isOn = CloudManager.shareActionShouldUpload
		actionUploadSwitch.tintColor = .lightGray

		updateiCloudControls()
	}

	override func darkModeChanged() {
		super.darkModeChanged()
		icloudSpinner.color = ViewController.tintColor
		icloudSwitch.onTintColor = view.tintColor
		limitToWiFiSwitch.onTintColor = view.tintColor
		actionUploadSwitch.onTintColor = view.tintColor
		eraseAlliCloudData.tintColor = view.tintColor
		if PersistedOptions.darkMode {
			for l in headerLabels {
				l.textColor = UIColor.lightGray
			}
			for s in subtitleLabels {
				s.textColor = UIColor.gray
			}
		} else {
			for l in headerLabels {
				l.textColor = UIColor.darkGray
			}
			for s in subtitleLabels {
				s.textColor = UIColor.gray
			}
		}
	}

	@IBAction func eraseiCloudDataSelected(_ sender: UIButton) {
		if CloudManager.syncSwitchedOn || CloudManager.syncTransitioning || CloudManager.syncing {
			genericAlert(title: "Sync is on", message: "This operation cannot be performed while sync is switched on. Please switch it off first.", on: self)
		} else {
			let a = UIAlertController(title: "Are you sure?", message: "This will remove any data that Gladys has stored in iCloud from any device. If you have other devices with sync switched on, it will stop working there until it is re-enabled.", preferredStyle: .alert)
			a.addAction(UIAlertAction(title: "Delete iCloud Data", style: .destructive, handler: { [weak self] action in
				self?.eraseiCloudData()
			}))
			a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
			present(a, animated: true)

		}
	}

	private func eraseiCloudData() {
		icloudSwitch.isEnabled = false
		eraseAlliCloudData.isEnabled = false
		syncNowButton.isEnabled = false
		self.eraseAlliCloudData.isEnabled = false
		CloudManager.eraseZoneIfNeeded { error in
			self.eraseAlliCloudData.isEnabled = true
			self.icloudSwitch.isEnabled = true
			if let error = error {
				genericAlert(title: "Error", message: error.finalDescription, on: self)
			} else {
				genericAlert(title: "Done", message: "All Gladys data has been removed from iCloud", on: self)
			}
		}
	}

	@objc private func icloudTransitionChanged() {
		updateiCloudControls()
		UIView.animate(animations: {
			self.view.layoutIfNeeded()
		}, completion: nil)
	}

	private func updateiCloudControls() {
		if CloudManager.syncTransitioning || CloudManager.syncing {
			icloudSwitch.isEnabled = false
			icloudLabel.text = CloudManager.syncString
			icloudSpinner.startAnimating()
		} else {
			icloudSwitch.isEnabled = true
			icloudLabel.text = "iCloud Sync"
			icloudSpinner.stopAnimating()
			icloudSwitch.isOn = CloudManager.syncSwitchedOn
		}
		eraseAlliCloudData.isEnabled = icloudSwitch.isEnabled
		syncNowButton.isEnabled = icloudSwitch.isEnabled && icloudSwitch.isOn
	}

	@IBAction func syncNowSelected(_ sender: UIBarButtonItem) {
		CloudManager.sync { error in
			DispatchQueue.main.async {
				if let error = error {
					genericAlert(title: "Sync Error", message: error.finalDescription, on: self)
				}
			}
		}
	}

	@objc private func icloudSwitchChanged() {
		if icloudSpinner.isAnimating { return }

		if icloudSwitch.isOn && !CloudManager.syncSwitchedOn {
			if Model.drops.count > 0 {
				let contentSize = diskSizeFormatter.string(fromByteCount: Model.sizeInBytes)
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
						genericAlert(title: "Could not change state", message: error.finalDescription, on: self)
					}
				}
			}
		}
	}

	private func proceedWithActivation() {
		CloudManager.activate { error in
			DispatchQueue.main.async {
				if let error = error {
					genericAlert(title: "Could not change state", message: error.finalDescription, on: self)
				}
			}
		}
	}
}
