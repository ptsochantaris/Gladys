//
//  iCloudController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 24/10/2017.
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
			if let s = subviews.first(where: { $0 is UILabel }) as? UILabel {
				return s.accessibilityLabel
			} else {
				return nil
			}
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

final class iCloudController: GladysViewController {

	@IBOutlet weak var icloudLabel: UILabel!
	@IBOutlet weak var icloudSwitch: UISwitch!
	@IBOutlet weak var icloudSpinner: UIActivityIndicatorView!
	@IBOutlet weak var limitToWiFiSwitch: UISwitch!
	@IBOutlet weak var eraseAlliCloudData: UIBarButtonItem!

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

	@IBAction func eraseiCloudDataSelected(_ sender: UIBarButtonItem) {
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
		UIApplication.shared.isNetworkActivityIndicatorVisible = true
		self.eraseAlliCloudData.isEnabled = false
		CloudManager.eraseZoneIfNeeded { error in
			self.eraseAlliCloudData.isEnabled = true
			self.icloudSwitch.isEnabled = true
			UIApplication.shared.isNetworkActivityIndicatorVisible = false
			if let error = error {
				genericAlert(title: "Error", message: error.localizedDescription, on: self)
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
