//
//  SiriShortcuts.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 09/02/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit
import IntentsUI

final class SiriShortcutsViewController: GladysViewController, INUIAddVoiceShortcutButtonDelegate, INUIAddVoiceShortcutViewControllerDelegate, INUIEditVoiceShortcutViewControllerDelegate {

	@IBOutlet private weak var openItemDetailContainer: UIView!
	@IBOutlet private weak var copyItemContainer: UIView!
	@IBOutlet private weak var quickLookItemContainer: UIView!
	@IBOutlet private weak var backgroundView: UIImageView!
	@IBOutlet private weak var stackHolder: UIView!
	@IBOutlet private weak var scrollView: UIScrollView!
	@IBOutlet private var headers: [UILabel]!
	@IBOutlet private var footers: [UILabel]!

	var detailActivity: NSUserActivity?
	var sourceItem: ArchivedDropItem?

	override func viewDidLoad() {
		super.viewDidLoad()

        backgroundView.backgroundColor = .white

        let style = INUIAddVoiceShortcutButtonStyle.black

		let detailShortcutButton = INUIAddVoiceShortcutButton(style: style)
		if let detailActivity = detailActivity {
			detailShortcutButton.shortcut = INShortcut(userActivity: detailActivity)
		}
		detailShortcutButton.place(in: openItemDetailContainer, buttonDelegate: self)

		let copyItemShortcutButton = INUIAddVoiceShortcutButton(style: style)
		if let sourceItem = sourceItem {
			copyItemShortcutButton.shortcut = INShortcut(intent: sourceItem.copyIntent)
		}
		copyItemShortcutButton.place(in: copyItemContainer, buttonDelegate: self)

		let quickLookShortcutButton = INUIAddVoiceShortcutButton(style: style)
		if let sourceItem = sourceItem {
			let previewActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
			ArchivedDropItem.updateUserActivity(previewActivity, from: sourceItem, child: nil, titled: "Quick look")
			quickLookShortcutButton.shortcut = INShortcut(userActivity: previewActivity)
		}
		quickLookShortcutButton.place(in: quickLookItemContainer, buttonDelegate: self)

        stackHolder.layoutIfNeeded()
		preferredContentSize = stackHolder.systemLayoutSizeFitting(.zero, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .fittingSizeLevel)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if stackHolder.frame.height > view.bounds.height {
			scrollView.flashScrollIndicators()
		}
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
