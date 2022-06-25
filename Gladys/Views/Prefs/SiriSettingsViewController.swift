import IntentsUI
import UIKit

final class SiriSettingsViewController: GladysViewController, INUIAddVoiceShortcutButtonDelegate, INUIAddVoiceShortcutViewControllerDelegate, INUIEditVoiceShortcutViewControllerDelegate {
    @IBOutlet private var pasteInGladysContainer: UIView!
    @IBOutlet private var stackHolder: UIView!
    @IBOutlet private var headers: [UILabel]!
    @IBOutlet private var footers: [UILabel]!

    override func viewDidLoad() {
        super.viewDidLoad()

        let pasteInGladysShortcutButton = INUIAddVoiceShortcutButton(style: .black)
        pasteInGladysShortcutButton.shortcut = INShortcut(intent: Model.pasteIntent)
        pasteInGladysContainer.cover(with: pasteInGladysShortcutButton)
        pasteInGladysShortcutButton.delegate = self

        preferredContentSize = stackHolder.systemLayoutSizeFitting(CGSize(width: 220, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
    }

    func present(_ addVoiceShortcutViewController: INUIAddVoiceShortcutViewController, for _: INUIAddVoiceShortcutButton) {
        addVoiceShortcutViewController.delegate = self
        addVoiceShortcutViewController.modalPresentationStyle = .formSheet
        addVoiceShortcutViewController.modalTransitionStyle = .crossDissolve
        present(addVoiceShortcutViewController, animated: true)
    }

    func present(_ editVoiceShortcutViewController: INUIEditVoiceShortcutViewController, for _: INUIAddVoiceShortcutButton) {
        editVoiceShortcutViewController.delegate = self
        editVoiceShortcutViewController.modalPresentationStyle = .formSheet
        editVoiceShortcutViewController.modalTransitionStyle = .crossDissolve
        present(editVoiceShortcutViewController, animated: true)
    }

    func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith _: INVoiceShortcut?, error _: Error?) {
        controller.dismiss(animated: true)
    }

    func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
        controller.dismiss(animated: true)
    }

    func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didUpdate _: INVoiceShortcut?, error _: Error?) {
        controller.dismiss(animated: true)
    }

    func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didDeleteVoiceShortcutWithIdentifier _: UUID) {
        controller.dismiss(animated: true)
    }

    func editVoiceShortcutViewControllerDidCancel(_ controller: INUIEditVoiceShortcutViewController) {
        controller.dismiss(animated: true)
    }
}
