//
//  TextEditController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 23/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit
import MobileCoreServices

protocol TextEditControllerDelegate: class {
	func textEditControllerMadeChanges(_ textEditController: TextEditController)
}

final class TextEditController: GladysViewController, UITextViewDelegate, LoadCompletionDelegate {

	weak var delegate: TextEditControllerDelegate?

	var item: ArchivedDropItem!
	var typeEntry: ArchivedDropItemType!
	var hasChanges = false
	var isAttributed = false

	@IBOutlet weak var textView: UITextView!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		doneLocation = .right

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
	}

	func textViewDidChange(_ textView: UITextView) {
		hasChanges = true
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if !hasChanges { return }

		if typeEntry.classWasWrapped {
			let d: Any = isAttributed ? textView.attributedText : textView.text
			typeEntry.bytes = NSKeyedArchiver.archivedData(withRootObject: d)
			saveDone()

		} else if isAttributed, let a = textView.attributedText {
			a.loadData(withTypeIdentifier: typeEntry.typeIdentifier) { data, error in
				DispatchQueue.main.async { [weak self] in
					self?.typeEntry.bytes = data
					self?.saveDone()
				}
			}

		} else if let t = textView.text {
			typeEntry.bytes = t.data(using: typeEntry.textEncoding)
			saveDone()
		}
	}

	func loadCompleted(sender: AnyObject) {
		Model.save()
		delegate?.textEditControllerMadeChanges(self)
	}

	private func saveDone() {
		typeEntry.markUpdated()
		item.markUpdated()
		item.needsReIngest = true
		_ = typeEntry.reIngest(delegate: self)
	}

}
