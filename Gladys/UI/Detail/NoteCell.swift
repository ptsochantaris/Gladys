import GladysCommon
import GladysUI
import UIKit

final class NoteCell: UITableViewCell, UITextViewDelegate {
    @IBOutlet private var placeholder: UILabel!

    @IBOutlet private var textView: UITextView!

    weak var delegate: ResizingCellDelegate?

    private var observer: NSKeyValueObservation?

    override func awakeFromNib() {
        super.awakeFromNib()
        textView.textContainerInset = .zero

        focusEffect = UIFocusHaloEffect()
        textView?.focusGroupIdentifier = "build.bru.gladys.detail.focus"

        let c = UIColor.g_colorTint
        textView.textColor = c
        placeholder.textColor = c
        observer = textView.observe(\.selectedTextRange, options: .new) { [weak self] _, _ in
            self?.caretMoved()
        }
    }

    func startEdit() {
        textView.becomeFirstResponder()
    }

    private func caretMoved() {
        guard let r = textView.selectedTextRange, let s = superview else {
            return
        }
        var caretRect = textView.caretRect(for: r.start)
        caretRect = textView.convert(caretRect, to: s)
        caretRect = caretRect.insetBy(dx: 0, dy: -22)
        delegate?.cellNeedsResize(cell: self, caretRect: caretRect, heightChange: false)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        previousText = nil
        previousHeight = 0
    }

    var item: ArchivedItem! {
        didSet {
            textView.text = item.note
            placeholder.isHidden = textView.hasText
        }
    }

    func textViewDidBeginEditing(_: UITextView) {
        previousText = item.note
        placeholder.isHidden = true
    }

    private var previousHeight: CGFloat = 0
    private var previousText: String?

    func textView(_: UITextView, shouldChangeTextIn _: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            caretMoved()
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        let newHeight = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: 5000)).height
        if previousHeight != newHeight {
            if let r = textView.selectedTextRange, let s = superview {
                var caretRect = textView.caretRect(for: r.start)
                caretRect = textView.convert(caretRect, to: s)
                caretRect = caretRect.insetBy(dx: 0, dy: -22)
                delegate?.cellNeedsResize(cell: self, caretRect: caretRect, heightChange: true)
            } else {
                delegate?.cellNeedsResize(cell: self, caretRect: nil, heightChange: false)
            }
            previousHeight = newHeight
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        let newText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        textView.text = newText

        placeholder.isHidden = !newText.isEmpty

        if previousText == newText {
            delegate?.cellNeedsResize(cell: self, caretRect: nil, heightChange: true)
            return
        }

        previousText = nil

        item.note = newText
        item.markUpdated()

        delegate?.cellNeedsResize(cell: self, caretRect: nil, heightChange: true)

        Task {
            await Model.save()
        }
    }

    /////////////////////////////////////

    override var accessibilityLabel: String? {
        get {
            placeholder.isHidden ? "Note" : "Add Note"
        }
        set {}
    }

    override var accessibilityValue: String? {
        get {
            textView.accessibilityValue
        }
        set {}
    }

    override var accessibilityHint: String? {
        get {
            placeholder.isHidden ? "Select to edit" : "Select to add a note"
        }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        textView.becomeFirstResponder()
        return true
    }

    override var isAccessibilityElement: Bool {
        get {
            !textView.isFirstResponder
        }
        set {}
    }
}
