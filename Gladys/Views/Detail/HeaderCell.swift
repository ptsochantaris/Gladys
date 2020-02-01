//
//  HeaderCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 23/09/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class HeaderCell: UITableViewCell, UITextViewDelegate {

	@IBOutlet private weak var label: UITextView!

	var item: ArchivedItem? {
		didSet {
			setLabelText()
		}
	}

	var resizeCallback: ((CGRect?, Bool) -> Void)?
    private var observer: NSKeyValueObservation?

	override func awakeFromNib() {
        super.awakeFromNib()
        label.textContainerInset = .zero
        observer = label.observe(\.selectedTextRange, options: .new) { [weak self] _, _ in
            self?.caretMoved()
        }
	}

    private func caretMoved() {
		if let r = label.selectedTextRange, let s = superview {
			var caretRect = label.caretRect(for: r.start)
			caretRect = label.convert(caretRect, to: s)
			caretRect = caretRect.insetBy(dx: 0, dy: -22)
			self.resizeCallback?(caretRect, false)
		}
	}

	private var previousText: String?
	private var previousHeight: CGFloat = 0

	override func prepareForReuse() {
		super.prepareForReuse()
		previousText = nil
		previousHeight = 0
	}

	func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
		if textView.alpha < 1 {
			textView.alpha = 1
			textView.text = nil
		}
		previousText = item?.displayText.0 ?? ""
		return true
	}

	func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
		textView.text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
		return true
	}

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
		if previousText == newText {
			setLabelText()
			resizeCallback?(nil, true)
			return
		}

		previousText = nil

		guard let item = item else { return }

		if newText.isEmpty || newText == item.nonOverridenText.0 {
			item.titleOverride = ""
		} else {
			item.titleOverride = newText
		}
		item.markUpdated()
		setLabelText()

		resizeCallback?(nil, true)

	    Model.save()
	}

	private func setLabelText() {
		if let text = item?.displayText.0, !text.isEmpty {
			label.text = text
			label.alpha = 1
		} else {
			label.text = "Title"
			label.alpha = 0.4
		}
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
			return !label.isFirstResponder
		}
	}
}
