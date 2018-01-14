//
//  HeaderCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 23/09/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class HeaderCell: UITableViewCell, UITextViewDelegate {

	@IBOutlet weak var label: UITextView!

	var item: ArchivedDropItem? {
		didSet {
			label.text = item?.displayText.0
		}
	}

	var resizeCallback: ((CGRect?, Bool)->Void)?

	override func awakeFromNib() {
		label.addObserver(self, forKeyPath: "selectedTextRange", options: .new, context: nil)
	}

	deinit {
		label.removeObserver(self, forKeyPath: "selectedTextRange")
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		caretMoved()
	}

	private func caretMoved() {
		if let r = label.selectedTextRange, let s = superview {
			var caretRect = label.caretRect(for: r.start)
			caretRect = label.convert(caretRect, to: s)
			caretRect = caretRect.insetBy(dx: 0, dy: -22)
			self.resizeCallback?(caretRect, false)
		}
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		dirty = false
		previousHeight = 0
	}

	func textViewDidBeginEditing(_ textView: UITextView) {
		dirty = false
	}

	func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
		textView.text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
		return true
	}

	private var previousHeight: CGFloat = 0
	private var dirty = false

	func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		if text == "\n" {
			caretMoved()
		}
		return true
	}

	func textViewDidChange(_ textView: UITextView) {
		dirty = true
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

		if !dirty { return }
		dirty = false

		guard let item = item else { return }

		let newText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
		if newText.isEmpty || newText == item.displayText.0 {
			item.titleOverride = ""
		} else {
			item.titleOverride = newText
		}
		item.markUpdated()
		label.text = item.displayText.0

		NotificationCenter.default.post(name: .ItemModified, object: item)
		resizeCallback?(nil, true)

		item.reIndex()
	    Model.save()
	}

	/////////////////////////////////////

	override var accessibilityLabel: String? {
		set {}
		get {
			return "Title"
		}
	}

	override var accessibilityValue: String? {
		set {}
		get {
			return label.accessibilityValue
		}
	}

	override var accessibilityHint: String? {
		set {}
		get {
			return "Select to edit"
		}
	}

	override func accessibilityActivate() -> Bool {
		label.becomeFirstResponder()
		return true
	}

	override var isAccessibilityElement: Bool {
		set {}
		get {
			return true
		}
	}
}
