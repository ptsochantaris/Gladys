import UIKit

@MainActor
protocol NotesEditorViewControllerDelegate: AnyObject {
    func newNoteSaved(note: String)
}

final class NotesEditorViewController: GladysViewController {
    var startupNote: String?
    weak var delegate: NotesEditorViewControllerDelegate?

    @IBOutlet private var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.text = startupNote
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        textView.becomeFirstResponder()
    }

    @IBAction private func saveSelected(_: UIBarButtonItem) {
        let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        delegate?.newNoteSaved(note: text)
        navigationController?.popViewController(animated: true)
    }
}
