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
	@IBOutlet private weak var scrollView: UIScrollView!
	@IBOutlet private var headers: [UILabel]!
	@IBOutlet private var footers: [UILabel]!

	var detailActivity: NSUserActivity?
	var sourceItem: ArchivedDropItem?

	override func viewDidLoad() {
		super.viewDidLoad()

		backgroundView.image = (ViewController.shared.itemView.backgroundView as! UIImageView).image

		let darkMode = PersistedOptions.darkMode
		let style: INUIAddVoiceShortcutButtonStyle = darkMode ? .blackOutline : .whiteOutline

		let detailShortcutButton = INUIAddVoiceShortcutButton(style: style)
		if let detailActivity = detailActivity {
			detailShortcutButton.shortcut = INShortcut(userActivity: detailActivity)
		}

		let copyItemShortcutButton = INUIAddVoiceShortcutButton(style: style)
		if let sourceItem = sourceItem {
			copyItemShortcutButton.shortcut = INShortcut(intent: sourceItem.copyIntent)
		}

		let quickLookShortcutButton = INUIAddVoiceShortcutButton(style: style)
		if let sourceItem = sourceItem {
			let previewActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
			ArchivedDropItem.updateUserActivity(previewActivity, from: sourceItem, child: nil, titled: "Quick look")
			quickLookShortcutButton.shortcut = INShortcut(userActivity: previewActivity)
		}

		func place(button: INUIAddVoiceShortcutButton, in holder: UIView) {
			button.delegate = self
			button.translatesAutoresizingMaskIntoConstraints = false
			holder.addSubview(button)
			let i = button.intrinsicContentSize
			NSLayoutConstraint.activate([
				button.widthAnchor.constraint(equalToConstant: i.width),
				button.heightAnchor.constraint(equalToConstant: i.height),
				button.topAnchor.constraint(equalTo: holder.topAnchor),
				button.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
				button.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
				button.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
			])
		}

		place(button: copyItemShortcutButton, in: copyItemContainer)
		place(button: detailShortcutButton, in: openItemDetailContainer)
		place(button: quickLookShortcutButton, in: quickLookItemContainer)

		preferredContentSize = stackHolder.systemLayoutSizeFitting(.zero, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .fittingSizeLevel)
	}

	override func darkModeChanged() {
		super.darkModeChanged()
		let d = PersistedOptions.darkMode

		let headerColor = d ? ViewController.tintColor : UIColor.darkGray
		headers.forEach { $0.textColor = headerColor }

		let footerColor = d ? UIColor.lightText : UIColor.gray
		footers.forEach { $0.textColor = footerColor }
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
