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
			label.text = item?.oneTitle
		}
	}

	var resizeCallback: ((CGRect?)->Void)?

	override func awakeFromNib() {
		label.addObserver(self, forKeyPath: "selectedTextRange", options: .new, context: nil)
	}

	deinit {
		label.removeObserver(self, forKeyPath: "selectedTextRange")
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		// caret moved
		if let r = label.selectedTextRange, let s = superview {
			var caretRect = label.caretRect(for: r.start)
			caretRect = label.convert(caretRect, to: s)
			caretRect = caretRect.insetBy(dx: 0, dy: -22)
			resizeCallback?(caretRect)
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

		if !dirty { return }
		dirty = false

		guard let item = item else { return }

		let newText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
		if newText.isEmpty || newText == item.oneTitle {
			item.titleOverride = ""
		} else {
			item.titleOverride = newText
		}
		item.updatedAt = Date()
		label.text = item.oneTitle

		NotificationCenter.default.post(name: .ItemModified, object: item)
		resizeCallback?(nil)
		
		item.makeIndex()
		
		let s = ViewController.shared!
		s.model.save()
	}
}
