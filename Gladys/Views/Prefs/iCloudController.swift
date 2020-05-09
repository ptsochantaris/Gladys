//
//  iCloudController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 24/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class iCloudController: GladysViewController {

	@IBOutlet private weak var icloudLabel: UILabel!
	@IBOutlet private weak var icloudSwitch: UISwitch!
	@IBOutlet private weak var icloudSpinner: UIActivityIndicatorView!
	@IBOutlet private weak var eraseAlliCloudData: UIButton!
	@IBOutlet private weak var syncNowButton: UIBarButtonItem!
    @IBOutlet private weak var syncPolicy: UISegmentedControl!
    
	override func viewDidLoad() {
		super.viewDidLoad()

		doneButtonLocation = .right

		NotificationCenter.default.addObserver(self, selector: #selector(icloudTransitionChanged), name: .CloudManagerStatusChanged, object: nil)

		icloudSwitch.isOn = CloudManager.syncSwitchedOn
		icloudSwitch.tintColor = UIColor(named: "colorLightGray")
		icloudSwitch.addTarget(self, action: #selector(icloudSwitchChanged), for: .valueChanged)

		updateiCloudControls()
	}

	@IBAction private func eraseiCloudDataSelected(_ sender: UIButton) {
		if CloudManager.syncSwitchedOn || CloudManager.syncTransitioning || CloudManager.syncing {
			genericAlert(title: "Sync is on", message: "This operation cannot be performed while sync is switched on. Please switch it off first.")
		} else {
			let a = UIAlertController(title: "Are you sure?", message: "This will remove any data that Gladys has stored in iCloud from any device. If you have other devices with sync switched on, it will stop working there until it is re-enabled.", preferredStyle: .alert)
			a.addAction(UIAlertAction(title: "Delete iCloud Data", style: .destructive) { [weak self] _ in
				self?.eraseiCloudData()
			})
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
				genericAlert(title: "Error", message: error.finalDescription)
			} else {
				genericAlert(title: "Done", message: "All Gladys data has been removed from iCloud")
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
			icloudSwitch.setOn(CloudManager.syncSwitchedOn, animated: true)
		}
		eraseAlliCloudData.isEnabled = icloudSwitch.isEnabled
		syncNowButton.isEnabled = icloudSwitch.isEnabled && icloudSwitch.isOn

        if icloudSwitch.isOn {
            syncPolicy.selectedSegmentIndex = CloudManager.syncContextSetting.rawValue
            syncPolicy.isEnabled = true
        } else {
            syncPolicy.selectedSegmentIndex = UISegmentedControl.noSegment
            syncPolicy.isEnabled = false
        }
	}
    
    @IBAction private func syncPolicyChanged(_ sender: UISegmentedControl) {
        if let newPolicy = CloudManager.SyncPermissionContext(rawValue: sender.selectedSegmentIndex) {
            CloudManager.syncContextSetting = newPolicy
        }
    }
    
	@IBAction private func syncNowSelected(_ sender: UIBarButtonItem) {
		CloudManager.sync { error in
			DispatchQueue.main.async {
				if let error = error {
					genericAlert(title: "Sync Error", message: error.finalDescription)
				}
			}
		}
	}

	@objc private func icloudSwitchChanged() {
		if icloudSpinner.isAnimating { return }

		if icloudSwitch.isOn && !CloudManager.syncSwitchedOn {
			if Model.drops.isEmpty {
                CloudManager.proceedWithActivation()
			} else {
                let contentSize = diskSizeFormatter.string(fromByteCount: Model.sizeInBytes)
                confirm(title: "Upload Existing Items?",
                        message: "If you have previously synced Gladys items they will merge with existing items.\n\nThis may upload up to \(contentSize) of data.\n\nIs it OK to proceed?",
                        action: "Proceed", cancel: "Cancel") { confirmed in
                    if confirmed {
                        CloudManager.proceedWithActivation()
                    } else {
                        self.icloudSwitch.setOn(false, animated: true)
                    }
                }
			}
		} else if CloudManager.syncSwitchedOn {
			let sharingOwn = Model.sharingMyItems
			let importing = Model.containsImportedShares
			if sharingOwn && importing {
				confirm(title: "You have shared items",
						message: "Turning sync off means that your currently shared items will be removed from others' collections, and their shared items will not be visible in your own collection. Is that OK?",
						action: "Turn Off Sync",
						cancel: "Cancel") { [weak self] confirmed in if confirmed { self?.deactivate() } else { self?.icloudSwitch.setOn(true, animated: true) } }
			} else if sharingOwn {
				confirm(title: "You are sharing items",
						message: "Turning sync off means that your currently shared items will be removed from others' collections. Is that OK?",
						action: "Turn Off Sync",
						cancel: "Cancel") { [weak self] confirmed in if confirmed { self?.deactivate() } else { self?.icloudSwitch.setOn(true, animated: true) } }
			} else if importing {
				confirm(title: "You have items that are shared from others",
						message: "Turning sync off means that those items will no longer be accessible. Re-activating sync will restore them later though. Is that OK?",
						action: "Turn Off Sync",
						cancel: "Cancel") { [weak self] confirmed in if confirmed { self?.deactivate() } else { self?.icloudSwitch.setOn(true, animated: true) } }
			} else {
				CloudManager.proceedWithDeactivation()
			}
		}
	}

	private func deactivate() {
		CloudManager.proceedWithDeactivation()
		updateiCloudControls()
	}

	private func confirm(title: String, message: String, action: String, cancel: String, completion: @escaping (Bool) -> Void) {
		let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
		a.addAction(UIAlertAction(title: action, style: .default) { _ in
			completion(true)
		})
		a.addAction(UIAlertAction(title: cancel, style: .cancel) { _ in
			completion(false)
		})
		present(a, animated: true)
	}
}
