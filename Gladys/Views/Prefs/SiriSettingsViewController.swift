//
//  SiriSettingsViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 10/02/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit
import IntentsUI

extension INUIAddVoiceShortcutButton {
	func place(in holder: UIView, buttonDelegate: INUIAddVoiceShortcutButtonDelegate, extraWidth: CGFloat = 0) {
		delegate = buttonDelegate
		translatesAutoresizingMaskIntoConstraints = false
		holder.addSubview(self)
		let i = intrinsicContentSize
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: i.width + extraWidth),
			heightAnchor.constraint(equalToConstant: i.height),
			topAnchor.constraint(equalTo: holder.topAnchor),
			bottomAnchor.constraint(equalTo: holder.bottomAnchor),
			leadingAnchor.constraint(equalTo: holder.leadingAnchor),
			trailingAnchor.constraint(equalTo: holder.trailingAnchor)
			])
	}
}

final class SiriSettingsViewController: GladysViewController, INUIAddVoiceShortcutButtonDelegate, INUIAddVoiceShortcutViewControllerDelegate, INUIEditVoiceShortcutViewControllerDelegate {

	@IBOutlet private var pasteInGladysContainer: UIView!
	@IBOutlet private var backgroundView: UIImageView!
	@IBOutlet private var stackHolder: UIView!
	@IBOutlet private var scrollView: UIScrollView!
	@IBOutlet private var headers: [UILabel]!
	@IBOutlet private var footers: [UILabel]!

	override func viewDidLoad() {
		super.viewDidLoad()

        backgroundView.backgroundColor = .white

		let style: INUIAddVoiceShortcutButtonStyle = .black

		let pasteInGladysShortcutButton = INUIAddVoiceShortcutButton(style: style)
		pasteInGladysShortcutButton.shortcut = INShortcut(intent: Model.pasteIntent)
		pasteInGladysShortcutButton.place(in: pasteInGladysContainer, buttonDelegate: self)

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
