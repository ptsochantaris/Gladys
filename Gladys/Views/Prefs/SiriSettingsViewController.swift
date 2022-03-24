//
//  SiriSettingsViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 10/02/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit
import IntentsUI

final class SiriSettingsViewController: GladysViewController, INUIAddVoiceShortcutButtonDelegate, INUIAddVoiceShortcutViewControllerDelegate, INUIEditVoiceShortcutViewControllerDelegate {

	@IBOutlet private var pasteInGladysContainer: UIView!
	@IBOutlet private var stackHolder: UIView!
	@IBOutlet private var headers: [UILabel]!
	@IBOutlet private var footers: [UILabel]!

	override func viewDidLoad() {
		super.viewDidLoad()

        let pasteInGladysShortcutButton = INUIAddVoiceShortcutButton(style: .black)
		pasteInGladysShortcutButton.shortcut = INShortcut(intent: Model.pasteIntent)
        pasteInGladysContainer.cover(with: pasteInGladysShortcutButton)
        pasteInGladysShortcutButton.delegate = self

        preferredContentSize = stackHolder.systemLayoutSizeFitting(CGSize(width: 220, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
	}

	func present(_ addVoiceShortcutViewController: INUIAddVoiceShortcutViewController, for addVoiceShortcutButton: INUIAddVoiceShortcutButton) {
		addVoiceShortcutViewController.delegate = self
		addVoiceShortcutViewController.modalPresentationStyle = .formSheet
		addVoiceShortcutViewController.modalTransitionStyle = .crossDissolve
		present(addVoiceShortcutViewController, animated: true)
	}

	func present(_ editVoiceShortcutViewController: INUIEditVoiceShortcutViewController, for addVoiceShortcutButton: INUIAddVoiceShortcutButton) {
		editVoiceShortcutViewController.delegate = self
		editVoiceShortcutViewController.modalPresentationStyle = .formSheet
		editVoiceShortcutViewController.modalTransitionStyle = .crossDissolve
		present(editVoiceShortcutViewController, animated: true)
	}

	func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: Error?) {
		controller.dismiss(animated: true)
	}

	func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
		controller.dismiss(animated: true)
	}

	func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didUpdate voiceShortcut: INVoiceShortcut?, error: Error?) {
		controller.dismiss(animated: true)
	}

	func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didDeleteVoiceShortcutWithIdentifier deletedVoiceShortcutIdentifier: UUID) {
		controller.dismiss(animated: true)
	}

	func editVoiceShortcutViewControllerDidCancel(_ controller: INUIEditVoiceShortcutViewController) {
		controller.dismiss(animated: true)
	}
}
