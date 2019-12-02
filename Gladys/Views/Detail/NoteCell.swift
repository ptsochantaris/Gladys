//
//  NotesCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 24/09/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class NoteCell: UITableViewCell, UITextViewDelegate {
	
	@IBOutlet private weak var placeholder: UILabel!

	@IBOutlet private weak var textView: UITextView!

	var resizeCallback: ((CGRect?, Bool)->Void)?

	override func awakeFromNib() {
		let c = UIColor(named: "colorTint")
		textView.textColor = c
		placeholder.textColor = c
		textView.addObserver(self, forKeyPath: "selectedTextRange", options: .new, context: nil)
	}

	deinit {
		textView.removeObserver(self, forKeyPath: "selectedTextRange")
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		caretMoved()
	}

	private func caretMoved() {
		if let r = textView.selectedTextRange, let s = superview {
			var caretRect = textView.caretRect(for: r.start)
			caretRect = textView.convert(caretRect, to: s)
			caretRect = caretRect.insetBy(dx: 0, dy: -22)
			self.resizeCallback?(caretRect, false)
		}
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		previousText = nil
		previousHeight = 0
	}

	var item: ArchivedDropItem! {
		didSet {
			textView.text = item.note
			placeholder.isHidden = textView.hasText
		}
	}

	func textViewDidBeginEditing(_ textView: UITextView) {
		previousText = item.note
		placeholder.isHidden = true
	}

	private var previousHeight: CGFloat = 0
	private var previousText: String?

	func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		if text == "\n" {
			caretMoved()
		}
		return true
	}

	func textViewDidChange(_ textView: UITextView) {
		let newHeight = textView.sizeThatFits(CGSize(width: frame.size.width, height: 5000)).height
		if previousHeight != newHeight {
			if let r = textView.selectedTextRange, let s = superview {
				var caretRect = textView.caretRect(for: r.start)
				caretRect = textView.convert(caretRect, to: s)
				caretRect = caretRect.insetBy(dx: 0, dy: -22)
				resizeCallback?(caretRect, true)
			} else {
				resizeCallback?(nil, true)
			}
			previousHeight = newHeight
		}
	}

	func textViewDidEndEditing(_ textView: UITextView) {

		let newText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
		textView.text = newText

		placeholder.isHidden = !newText.isEmpty

		if previousText == newText {
			resizeCallback?(nil, true)
			return
		}

		previousText = nil

		item.note = newText
		item.markUpdated()

		item.postModified()
		resizeCallback?(nil, true)

	    Model.save()
	}

	/////////////////////////////////////

	override var accessibilityLabel: String? {
		set {}
		get {
			return placeholder.isHidden ? "Note" : "Add Note"
		}
	}

	override var accessibilityValue: String? {
		set {}
		get {
			return textView.accessibilityValue
		}
	}

	override var accessibilityHint: String? {
		set {}
		get {
			return placeholder.isHidden ? "Select to edit" : "Select to add a note"
		}
	}

	override func accessibilityActivate() -> Bool {
		textView.becomeFirstResponder()
		return true
	}

	override var isAccessibilityElement: Bool {
		set {}
		get {
			return !textView.isFirstResponder
		}
	}
}
