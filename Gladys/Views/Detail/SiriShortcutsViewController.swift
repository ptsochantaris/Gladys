import IntentsUI
import UIKit

final class SiriShortcutsViewController: GladysViewController, INUIAddVoiceShortcutButtonDelegate, INUIAddVoiceShortcutViewControllerDelegate, INUIEditVoiceShortcutViewControllerDelegate {
    @IBOutlet private var openItemDetailContainer: UIView!
    @IBOutlet private var copyItemContainer: UIView!
    @IBOutlet private var quickLookItemContainer: UIView!

    var sourceItem: ArchivedItem?

    override func viewDidLoad() {
        super.viewDidLoad()

        let detailShortcutButton = INUIAddVoiceShortcutButton(style: .black)
        if let sourceItem {
            let activity = NSUserActivity(activityType: kGladysDetailViewingActivity)
            ArchivedItem.updateUserActivity(activity, from: sourceItem, child: nil, titled: "Info of")
            detailShortcutButton.shortcut = INShortcut(userActivity: activity)
        }
        detailShortcutButton.delegate = self
        openItemDetailContainer.cover(with: detailShortcutButton)

        let copyItemShortcutButton = INUIAddVoiceShortcutButton(style: .black)
        if let sourceItem {
            copyItemShortcutButton.shortcut = INShortcut(intent: sourceItem.copyIntent)
        }
        copyItemShortcutButton.delegate = self
        copyItemContainer.cover(with: copyItemShortcutButton)

        let quickLookShortcutButton = INUIAddVoiceShortcutButton(style: .black)
        if let sourceItem {
            let previewActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
            ArchivedItem.updateUserActivity(previewActivity, from: sourceItem, child: nil, titled: "Quick look")
            quickLookShortcutButton.shortcut = INShortcut(userActivity: previewActivity)
        }
        quickLookShortcutButton.delegate = self
        quickLookItemContainer.cover(with: quickLookShortcutButton)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        preferredContentSize = view.systemLayoutSizeFitting(CGSize(width: 220, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
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
