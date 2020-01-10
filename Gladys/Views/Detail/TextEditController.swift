//
//  TextEditController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 23/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit
import MobileCoreServices
import GladysFramework

protocol TextEditControllerDelegate: class {
	func textEditControllerMadeChanges(_ textEditController: TextEditController)
}

final class TextEditController: GladysViewController, UITextViewDelegate, ComponentIngestionDelegate {

	weak var delegate: TextEditControllerDelegate?

	var item: ArchivedItem!
	var typeEntry: Component!
	var hasChanges = false
	var isAttributed = false

	@IBOutlet private weak var bottomDistance: NSLayoutConstraint!
	@IBOutlet private weak var textView: UITextView!
	@IBOutlet private weak var backgroundView: UIImageView!

	override func viewDidLoad() {
		super.viewDidLoad()
		doneButtonLocation = .right

		if let decoded = typeEntry.decode() {

			if let data = decoded as? Data {
				// not wrapped
				if typeEntry.isRichText {
					textView.attributedText = try? NSAttributedString(data: data, options: [:], documentAttributes: nil)
					isAttributed = true
				} else {
					textView.text = String(data: data, encoding: typeEntry.textEncoding)
				}
			} else if let text = decoded as? String {
				// wrapped
				textView.text = text
			} else if let text = decoded as? NSAttributedString {
				// wrapped
				textView.attributedText = text
				isAttributed = true
			}
		}

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(keyboardHiding(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
		n.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
	}

	@objc private func keyboardHiding(_ notification: Notification) {
		if let u = notification.userInfo, let previousState = u[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect, !previousState.isEmpty {
			bottomDistance.constant = 0
		}
	}

	@objc private func keyboardChanged(_ notification: Notification) {
		guard let userInfo = notification.userInfo, let keyboardFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }

		let keyboardFrameInView = view.convert(keyboardFrame, from: nil)
		let safeAreaFrame = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 0, dy: -additionalSafeAreaInsets.bottom)
		let intersection = safeAreaFrame.intersection(keyboardFrameInView)

		if intersection.isNull {
			bottomDistance.constant = 0
		} else {
			bottomDistance.constant = (safeAreaFrame.origin.y + safeAreaFrame.size.height) - intersection.origin.y
		}
	}

	func textViewDidChange(_ textView: UITextView) {
		hasChanges = true
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if !hasChanges { return }

		if typeEntry.classWasWrapped, let d: Any = (isAttributed ? textView.attributedText : textView.text) {
			let b = SafeArchiver.archive(d) ?? Data()
			typeEntry.setBytes(b)
			saveDone()

		} else if isAttributed, let a = textView.attributedText {
			if typeEntry.typeIdentifier == (kUTTypeRTF as String) {
				let b = try? a.data(from: NSMakeRange(0, a.length), documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtf])
				typeEntry.setBytes(b)
				saveDone()
			} else if typeEntry.typeIdentifier == (kUTTypeRTFD as String) {
				let b = try? a.data(from: NSMakeRange(0, a.length), documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtfd])
				typeEntry.setBytes(b)
				saveDone()
			} else {
				a.loadData(withTypeIdentifier: typeEntry.typeIdentifier) { data, error in
					DispatchQueue.main.async { [weak self] in
						self?.typeEntry.setBytes(data)
						self?.saveDone()
					}
				}
			}

		} else if let t = textView.text {
			let b = t.data(using: typeEntry.textEncoding)
			typeEntry.setBytes(b)
			saveDone()
		}
	}

	func componentIngested(typeItem: Component?) {
		Model.save()
		delegate?.textEditControllerMadeChanges(self)
	}

	private func saveDone() {
		typeEntry.markUpdated()
		item.markUpdated()
		item.needsReIngest = true
		_ = typeEntry.reIngest(delegate: self)
	}

	override var keyCommands: [UIKeyCommand]? {
		let a = super.keyCommands ?? []
		return a.filter {
			return !($0.input == UIKeyCommand.inputUpArrow || $0.input == UIKeyCommand.inputDownArrow)
		}
	}

}
