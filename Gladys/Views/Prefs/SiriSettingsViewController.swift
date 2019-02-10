//
//  SiriSettingsViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 10/02/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit
import IntentsUI

@available(iOS 12.0, *)
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
			trailingAnchor.constraint(equalTo: holder.trailingAnchor),
			])
	}
}

@available(iOS 12.0, *)
final class SiriSettingsViewController: GladysViewController, INUIAddVoiceShortcutButtonDelegate, INUIAddVoiceShortcutViewControllerDelegate, INUIEditVoiceShortcutViewControllerDelegate {

	@IBOutlet private weak var pasteInGladysContainer: UIView!
	@IBOutlet private weak var backgroundView: UIImageView!
	@IBOutlet private weak var stackHolder: UIView!
	@IBOutlet private weak var scrollView: UIScrollView!
	@IBOutlet private var headers: [UILabel]!
	@IBOutlet private var footers: [UILabel]!

	override func viewDidLoad() {
		super.viewDidLoad()

		if PersistedOptions.darkMode {
			backgroundView.backgroundColor = .darkGray
		} else {
			backgroundView.backgroundColor = .white
		}

		let darkMode = PersistedOptions.darkMode
		let style: INUIAddVoiceShortcutButtonStyle = darkMode ? .white : .black

		let pasteInGladysShortcutButton = INUIAddVoiceShortcutButton(style: style)
		pasteInGladysShortcutButton.shortcut = INShortcut(intent: ViewController.shared.pasteIntent)
		pasteInGladysShortcutButton.place(in: pasteInGladysContainer, buttonDelegate: self)

		preferredContentSize = stackHolder.systemLayoutSizeFitting(.zero, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .fittingSizeLevel)
	}

	override func darkModeChanged() {
		super.darkModeChanged()
		let d = PersistedOptions.darkMode

		let color: UIColor = d ? .lightText : .gray
		headers.forEach { $0.textColor = color }
		footers.forEach { $0.textColor = color }
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
