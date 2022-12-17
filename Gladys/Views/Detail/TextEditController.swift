import GladysFramework
import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

protocol TextEditControllerDelegate: AnyObject {
    func textEditControllerMadeChanges(_ textEditController: TextEditController)
}

final class TextEditController: GladysViewController, UITextViewDelegate {
    weak var delegate: TextEditControllerDelegate?

    var item: ArchivedItem!
    var typeEntry: Component!
    var hasChanges = false
    var isAttributed = false

    @IBOutlet private var bottomDistance: NSLayoutConstraint!
    @IBOutlet private var textView: UITextView!
    @IBOutlet private var backgroundView: UIImageView!

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

    func textViewDidChange(_: UITextView) {
        hasChanges = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !hasChanges { return }

        if typeEntry.classWasWrapped, let d: Any = (isAttributed ? textView.attributedText : textView.text) {
            let b = SafeArchiving.archive(d) ?? emptyData
            typeEntry.setBytes(b)
            saveDone()

        } else if isAttributed, let a = textView.attributedText {
            if typeEntry.typeIdentifier == UTType.rtf.identifier {
                let b = try? a.data(from: NSRange(location: 0, length: a.length), documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtf])
                typeEntry.setBytes(b)
                saveDone()
            } else if typeEntry.typeIdentifier == UTType.rtfd.identifier {
                let b = try? a.data(from: NSRange(location: 0, length: a.length), documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtfd])
                typeEntry.setBytes(b)
                saveDone()
            } else {
                a.loadData(withTypeIdentifier: typeEntry.typeIdentifier) { data, _ in
                    Task { @MainActor [weak self] in
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

    private func saveDone() {
        typeEntry.markUpdated()
        item.markUpdated()
        item.needsReIngest = true
        Task {
            try? await typeEntry.reIngest()
            Model.save()
            self.delegate?.textEditControllerMadeChanges(self)
        }
    }
}
