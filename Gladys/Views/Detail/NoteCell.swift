//
//  NotesCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 24/09/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class NoteCell: UITableViewCell, UITextViewDelegate {
	
	@IBOutlet weak var placeholder: UILabel!

	@IBOutlet weak var textView: UITextView!

	var resizeCallback: ((CGRect?)->Void)?

	override func awakeFromNib() {
		textView.addObserver(self, forKeyPath: "selectedTextRange", options: .new, context: nil)
	}

	deinit {
		textView.removeObserver(self, forKeyPath: "selectedTextRange")
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		// caret moved
		if let r = textView.selectedTextRange, let s = superview {
			var caretRect = textView.caretRect(for: r.start)
			caretRect = textView.convert(caretRect, to: s)
			caretRect = caretRect.insetBy(dx: 0, dy: -22)
			resizeCallback?(caretRect)
		}
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		dirty = false
		previousHeight = 0
	}

	var item: ArchivedDropItem! {
		didSet {
			textView.text = item.note
			placeholder.isHidden = textView.hasText
		}
	}

	func textViewDidBeginEditing(_ textView: UITextView) {
		dirty = false
		placeholder.isHidden = true
	}

	func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
		textView.text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
		return true
	}

	private var previousHeight: CGFloat = 0
	private var dirty = false

	func textViewDidChange(_ textView: UITextView) {
		dirty = true
		let newHeight = sizeThatFits(CGSize(width: frame.size.width, height: 5000)).height
		if previousHeight != newHeight {
			if let r = textView.selectedTextRange, let s = superview {
				var caretRect = textView.caretRect(for: r.start)
				caretRect = textView.convert(caretRect, to: s)
				caretRect = caretRect.insetBy(dx: 0, dy: -22)
				resizeCallback?(caretRect)
			} else {
				resizeCallback?(nil)
			}
		}
	}

	func textViewDidEndEditing(_ textView: UITextView) {

		placeholder.isHidden = textView.hasText

		if !dirty { return }
		dirty = false

		item.note = textView.text
		item.markUpdated()

		NotificationCenter.default.post(name: .ItemModified, object: item)
		resizeCallback?(nil)

		item.reIndex()
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
			return true
		}
	}
}
