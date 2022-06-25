import UIKit

final class HeaderCell: UITableViewCell, UITextViewDelegate {
    @IBOutlet private var label: UITextView!

    var item: ArchivedItem? {
        didSet {
            setLabelText()
        }
    }

    weak var delegate: ResizingCellDelegate?

    private var observer: NSKeyValueObservation?

    override func awakeFromNib() {
        super.awakeFromNib()
        label.textContainerInset = .zero
        observer = label.observe(\.selectedTextRange, options: .new) { [weak self] _, _ in
            self?.caretMoved()
        }

        if #available(iOS 15.0, *) {
            self.focusEffect = UIFocusHaloEffect()
            label.focusGroupIdentifier = "build.bru.gladys.detail.focus"
        }
    }

    func startEdit() {
        label.becomeFirstResponder()
    }

    private func caretMoved() {
        if let r = label.selectedTextRange, let s = superview {
            var caretRect = label.caretRect(for: r.start)
            caretRect = label.convert(caretRect, to: s)
            caretRect = caretRect.insetBy(dx: 0, dy: -22)
            delegate?.cellNeedsResize(cell: self, caretRect: caretRect, heightChange: false)
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

    func textView(_: UITextView, shouldChangeTextIn _: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            caretMoved()
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        let newHeight = textView.sizeThatFits(CGSize(width: textView.bounds.size.width, height: 5000)).height
        if previousHeight != newHeight {
            if let r = textView.selectedTextRange, let s = superview {
                var caretRect = textView.caretRect(for: r.start)
                caretRect = textView.convert(caretRect, to: s)
                caretRect = caretRect.insetBy(dx: 0, dy: -22)
                delegate?.cellNeedsResize(cell: self, caretRect: caretRect, heightChange: true)
            } else {
                delegate?.cellNeedsResize(cell: self, caretRect: nil, heightChange: true)
            }
            previousHeight = newHeight
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        let newText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if previousText == newText {
            setLabelText()
            delegate?.cellNeedsResize(cell: self, caretRect: nil, heightChange: true)
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

        delegate?.cellNeedsResize(cell: self, caretRect: nil, heightChange: true)

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
        get {
            "Title"
        }
        set {}
    }

    override var accessibilityValue: String? {
        get {
            label.accessibilityValue
        }
        set {}
    }

    override var accessibilityHint: String? {
        get {
            "Select to edit"
        }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        label.becomeFirstResponder()
        return true
    }

    override var isAccessibilityElement: Bool {
        get {
            !label.isFirstResponder
        }
        set {}
    }
}
