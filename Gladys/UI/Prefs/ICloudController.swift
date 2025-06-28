import GladysCommon
import GladysUI
import GladysUIKit
import UIKit

final class ICloudController: GladysViewController {
    @IBOutlet private var icloudLabel: UILabel!
    @IBOutlet private var icloudSwitch: UISwitch!
    @IBOutlet private var icloudSpinner: UIActivityIndicatorView!
    @IBOutlet private var eraseAlliCloudData: UIButton!
    @IBOutlet private var syncNowButton: UIBarButtonItem!
    @IBOutlet private var syncPolicy: UISegmentedControl!

    override func viewDidLoad() {
        super.viewDidLoad()

        doneButtonLocation = .right

        notifications(for: .CloudManagerStatusChanged) { [weak self] _ in
            await self?.updateiCloudControls()
        }

        icloudSwitch.tintColor = UIColor.g_colorLightGray

        Task {
            icloudSwitch.isOn = await CloudManager.syncSwitchedOn
            icloudSwitch.addTarget(self, action: #selector(icloudSwitchChanged), for: .valueChanged)
            await updateiCloudControls()
        }
    }

    @IBAction private func eraseiCloudDataSelected(_: UIButton) {
        Task {
            await _eraseiCloudDataSelected()
        }
    }

    private func _eraseiCloudDataSelected() async {
        let syncOn = await CloudManager.syncSwitchedOn
        let transitioning = await CloudManager.syncTransitioning
        let syncing = await CloudManager.syncing
        if syncOn || transitioning || syncing {
            await genericAlert(title: "Sync is on", message: "This operation cannot be performed while sync is switched on. Please switch it off first.")
        } else {
            let a = UIAlertController(title: "Are you sure?", message: "This will remove any data that Gladys has stored in iCloud from any device. If you have other devices with sync switched on, it will stop working there until it is re-enabled.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Delete iCloud Data", style: .destructive) { [weak self] _ in
                guard let self else { return }
                eraseiCloudData()
            })
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(a, animated: true)
        }
    }

    private func eraseiCloudData() {
        icloudSwitch.isEnabled = false
        eraseAlliCloudData.isEnabled = false
        syncNowButton.isEnabled = false
        eraseAlliCloudData.isEnabled = false
        Task {
            do {
                try await CloudManager.eraseZoneIfNeeded()
                await genericAlert(title: "Done", message: "All Gladys data has been removed from iCloud")
            } catch {
                await genericAlert(title: "Error", message: error.localizedDescription)
            }
            icloudSwitch.isEnabled = true
            eraseAlliCloudData.isEnabled = true
        }
    }

    private func updateiCloudControls() async {
        let transitioning = await CloudManager.syncTransitioning
        let syncing = await CloudManager.syncing
        if transitioning || syncing {
            icloudSwitch.isEnabled = false
            let swiftString = await CloudManager.makeSyncString()
            icloudLabel.text = swiftString
            icloudSpinner.startAnimating()
        } else {
            icloudSwitch.isEnabled = true
            icloudLabel.text = "iCloud Sync"
            icloudSpinner.stopAnimating()
            await icloudSwitch.setOn(CloudManager.syncSwitchedOn, animated: true)
        }
        eraseAlliCloudData.isEnabled = icloudSwitch.isEnabled
        syncNowButton.isEnabled = icloudSwitch.isEnabled && icloudSwitch.isOn

        if icloudSwitch.isOn {
            syncPolicy.selectedSegmentIndex = await CloudManager.syncContextSetting.rawValue
            syncPolicy.isEnabled = true
        } else {
            syncPolicy.selectedSegmentIndex = UISegmentedControl.noSegment
            syncPolicy.isEnabled = false
        }
    }

    @IBAction private func syncPolicyChanged(_ sender: UISegmentedControl) {
        guard let newPolicy = CloudManager.SyncPermissionContext(rawValue: sender.selectedSegmentIndex) else {
            return
        }
        Task { @CloudActor in
            CloudManager.syncContextSetting = newPolicy
            if newPolicy == .manualOnly {
                await genericAlert(title: "Manual sync warning", message: "This is an advanced setting that disables all syncing unless explicitly requested. It is best used as a temporary setting if items with large sizes need to be temporarily added without triggering long syncs.")
            }
        }
    }

    @IBAction private func syncNowSelected(_: UIBarButtonItem) {
        Task {
            do {
                try await CloudManager.sync()
            } catch {
                await genericAlert(title: "Sync Error", message: error.localizedDescription)
            }
        }
    }

    @objc private func icloudSwitchChanged() {
        Task {
            let syncOn = await CloudManager.syncSwitchedOn

            if icloudSpinner.isAnimating {
                icloudSwitch.isOn = syncOn
                return
            }

            if icloudSwitch.isOn, !syncOn {
                if DropStore.allDrops.isEmpty {
                    await activate()
                } else {
                    let contentSize = await DropStore.sizeInBytes()
                    let contentSizeString = diskSizeFormat.format(contentSize)
                    let confirmed = await confirm(title: "Upload Existing Items?",
                                                  message: "If you have previously synced Gladys items they will merge with existing items.\n\nThis may upload up to \(contentSizeString) of data.\n\nIs it OK to proceed?",
                                                  action: "Proceed", cancel: "Cancel")
                    if confirmed {
                        await activate()
                    } else {
                        icloudSwitch.setOn(false, animated: true)
                    }
                }

            } else if !icloudSwitch.isOn, syncOn {
                let sharingOwn = DropStore.sharingMyItems
                let importing = DropStore.containsImportedShares
                let confirmed = if sharingOwn, importing {
                    await confirm(title: "You have shared items",
                                  message: "Turning sync off means that your currently shared items will be removed from others' collections, and their shared items will not be visible in your own collection. Is that OK?",
                                  action: "Turn Off Sync",
                                  cancel: "Cancel")
                } else if sharingOwn {
                    await confirm(title: "You are sharing items",
                                  message: "Turning sync off means that your currently shared items will be removed from others' collections. Is that OK?",
                                  action: "Turn Off Sync",
                                  cancel: "Cancel")
                } else if importing {
                    await confirm(title: "You have items that are shared from others",
                                  message: "Turning sync off means that those items will no longer be accessible. Re-activating sync will restore them later though. Is that OK?",
                                  action: "Turn Off Sync",
                                  cancel: "Cancel")
                } else {
                    true
                }

                if confirmed {
                    await deactivate()
                } else {
                    icloudSwitch.setOn(true, animated: true)
                }
            }
        }
    }

    private func activate() async {
        do {
            try await CloudManager.startActivation()
        } catch {
            let offerSettings = (error as? GladysError)?.suggestSettings ?? false
            await genericAlert(title: "Could not activate", message: error.localizedDescription, offerSettingsShortcut: offerSettings)
        }
    }

    private func deactivate() async {
        do {
            try await CloudManager.proceedWithDeactivation()
        } catch {
            await genericAlert(title: "Could not deactivate", message: error.localizedDescription)
        }
        await updateiCloudControls()
    }
}
