//
//  SiriShortcuts.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 09/02/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit
import IntentsUI

@available(iOS 12.0, *)
final class SiriShortcutsViewController: GladysViewController, INUIAddVoiceShortcutButtonDelegate, INUIAddVoiceShortcutViewControllerDelegate, INUIEditVoiceShortcutViewControllerDelegate {

	@IBOutlet private weak var openItemDetailContainer: UIView!
	@IBOutlet private weak var copyItemContainer: UIView!
	@IBOutlet private weak var quickLookItemContainer: UIView!
	@IBOutlet private weak var backgroundView: UIImageView!
	@IBOutlet private weak var stackHolder: UIView!

	var detailActivity: NSUserActivity?
	var sourceItem: ArchivedDropItem?

	override func viewDidLoad() {
		super.viewDidLoad()

		backgroundView.image = (ViewController.shared.itemView.backgroundView as! UIImageView).image

		let style: INUIAddVoiceShortcutButtonStyle = PersistedOptions.darkMode ? .black : .white

		let detailShortcutButton = INUIAddVoiceShortcutButton(style: style)
		detailShortcutButton.translatesAutoresizingMaskIntoConstraints = false
		detailShortcutButton.delegate = self
		if let detailActivity = detailActivity {
			detailShortcutButton.shortcut = INShortcut(userActivity: detailActivity)
		}
		openItemDetailContainer.addSubview(detailShortcutButton)

		let copyItemShortcutButton = INUIAddVoiceShortcutButton(style: style)
		copyItemShortcutButton.translatesAutoresizingMaskIntoConstraints = false
		copyItemShortcutButton.delegate = self
		if let sourceItem = sourceItem {
			copyItemShortcutButton.shortcut = INShortcut(intent: sourceItem.copyIntent)
		}
		copyItemContainer.addSubview(copyItemShortcutButton)

		let quickLookShortcutButton = INUIAddVoiceShortcutButton(style: style)
		quickLookShortcutButton.translatesAutoresizingMaskIntoConstraints = false
		quickLookShortcutButton.delegate = self
		if let sourceItem = sourceItem {
			let previewActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
			ArchivedDropItem.updateUserActivity(previewActivity, from: sourceItem, child: nil, titled: "Quick look")
			quickLookShortcutButton.shortcut = INShortcut(userActivity: previewActivity)
		}
		quickLookItemContainer.addSubview(quickLookShortcutButton)

		NSLayoutConstraint.activate([
			detailShortcutButton.centerXAnchor.constraint(equalTo: openItemDetailContainer.centerXAnchor),
			detailShortcutButton.topAnchor.constraint(equalTo: openItemDetailContainer.topAnchor),
			detailShortcutButton.bottomAnchor.constraint(equalTo: openItemDetailContainer.bottomAnchor),
			detailShortcutButton.leadingAnchor.constraint(greaterThanOrEqualTo: openItemDetailContainer.leadingAnchor),
			detailShortcutButton.trailingAnchor.constraint(greaterThanOrEqualTo: openItemDetailContainer.trailingAnchor),

			copyItemShortcutButton.centerXAnchor.constraint(equalTo: copyItemContainer.centerXAnchor),
			copyItemShortcutButton.topAnchor.constraint(equalTo: copyItemContainer.topAnchor),
			copyItemShortcutButton.bottomAnchor.constraint(equalTo: copyItemContainer.bottomAnchor),
			copyItemShortcutButton.leadingAnchor.constraint(greaterThanOrEqualTo: copyItemContainer.leadingAnchor),
			copyItemShortcutButton.trailingAnchor.constraint(greaterThanOrEqualTo: copyItemContainer.trailingAnchor),

			quickLookShortcutButton.centerXAnchor.constraint(equalTo: quickLookItemContainer.centerXAnchor),
			quickLookShortcutButton.topAnchor.constraint(equalTo: quickLookItemContainer.topAnchor),
			quickLookShortcutButton.bottomAnchor.constraint(equalTo: quickLookItemContainer.bottomAnchor),
			quickLookShortcutButton.leadingAnchor.constraint(greaterThanOrEqualTo: quickLookItemContainer.leadingAnchor),
			quickLookShortcutButton.trailingAnchor.constraint(greaterThanOrEqualTo: quickLookItemContainer.trailingAnchor),
			])
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		guard let stackHolder = stackHolder else { return }
		preferredContentSize = stackHolder.systemLayoutSizeFitting(.zero, withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .fittingSizeLevel)
	}

	func present(_ addVoiceShortcutViewController: INUIAddVoiceShortcutViewController, for addVoiceShortcutButton: INUIAddVoiceShortcutButton) {
		addVoiceShortcutViewController.delegate = self
		addVoiceShortcutViewController.modalPresentationStyle = .formSheet
		addVoiceShortcutViewController.modalTransitionStyle = .crossDissolve
		present(addVoiceShortcutViewController, animated: true, completion: nil)
	}

	func present(_ editVoiceShortcutViewController: INUIEditVoiceShortcutViewController, for addVoiceShortcutButton: INUIAddVoiceShortcutButton) {
		editVoiceShortcutViewController.delegate = self
		editVoiceShortcutViewController.modalPresentationStyle = .formSheet
		editVoiceShortcutViewController.modalTransitionStyle = .crossDissolve
		present(editVoiceShortcutViewController, animated: true, completion: nil)
	}

	func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: Error?) {
		controller.dismiss(animated: true, completion: nil)
	}

	func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
		controller.dismiss(animated: true, completion: nil)
	}

	func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didUpdate voiceShortcut: INVoiceShortcut?, error: Error?) {
		controller.dismiss(animated: true, completion: nil)
	}

	func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didDeleteVoiceShortcutWithIdentifier deletedVoiceShortcutIdentifier: UUID) {
		controller.dismiss(animated: true, completion: nil)
	}

	func editVoiceShortcutViewControllerDidCancel(_ controller: INUIEditVoiceShortcutViewController) {
		controller.dismiss(animated: true, completion: nil)
	}
}
