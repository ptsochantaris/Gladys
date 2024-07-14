import GladysCommon
import GladysUI
import GladysUIKit
import Speech
import UIKit

final class OptionsController: GladysViewController, UIPopoverPresentationControllerDelegate {
    @IBOutlet private var twoColumnsSwitch: UISwitch!
    @IBOutlet private var separateItemsSwitch: UISwitch!
    @IBOutlet private var removeItemsWhenDraggedOutSwitch: UISwitch!
    @IBOutlet private var dontAutoLabelNewItemsSwitch: UISwitch!
    @IBOutlet private var displayNotesInMainViewSwitch: UISwitch!
    @IBOutlet private var showCopyMoveSwitchSelectorSwitch: UISwitch!
    @IBOutlet private var fullScreenSwitch: UISwitch!
    @IBOutlet private var fullScreenHolder: SwitchHolder!
    @IBOutlet private var displayLabelsInMainViewSwitch: UISwitch!
    @IBOutlet private var allowLabelsInExtensionSwitch: UISwitch!
    @IBOutlet private var wideModeSwitch: UISwitch!
    @IBOutlet private var autoConvertUrlsSwitch: UISwitch!
    @IBOutlet private var blockGladysUrls: UISwitch!
    @IBOutlet private var generateLabelsFromTitlesSwitch: UISwitch!
    @IBOutlet private var generateLabelsFromThumbnailsSwitch: UISwitch!
    @IBOutlet private var generateTextFromThumbnailsSwitch: UISwitch!
    @IBOutlet private var transcribeSpeechInMedia: UISwitch!
    @IBOutlet private var applyMlToUrlsSwitch: UISwitch!
    @IBOutlet private var badgeIconSwitch: UISwitch!
    @IBOutlet private var requestInlineDrops: UISwitch!

    @IBOutlet private var actionSelector: UISegmentedControl!
    @IBOutlet private var autoArchiveSwitch: UISwitch!
    @IBOutlet private var exclusiveLabelsSwitch: UISwitch!

    @IBOutlet private var searchSelector: UISegmentedControl!
    @IBOutlet private var searchDescription: UILabel!

    @IBAction private func wideModeSwitchSelected(_ sender: UISwitch) {
        PersistedOptions.wideMode = sender.isOn
        sendNotification(name: .ItemCollectionNeedsDisplay, object: true)
    }

    @IBAction private func allowLabelsInExtensionSwitchSelected(_ sender: UISwitch) {
        PersistedOptions.setLabelsWhenActioning = sender.isOn
    }

    @IBAction private func displayLabelsInMainViewSwitchSelected(_ sender: UISwitch) {
        PersistedOptions.displayLabelsInMainView = sender.isOn
        sendNotification(name: .ItemCollectionNeedsDisplay)
    }

    @IBAction private func showCopyMoveSwitchSelectorSwitchChanged(_ sender: UISwitch) {
        PersistedOptions.showCopyMoveSwitchSelector = sender.isOn
    }

    @IBAction private func removeItemsWhenDraggedOutChanged(_ sender: UISwitch) {
        PersistedOptions.removeItemsWhenDraggedOut = sender.isOn
    }

    @IBAction private func dontAutoLabelNewItemsChanged(_ sender: UISwitch) {
        PersistedOptions.dontAutoLabelNewItems = sender.isOn
    }

    @IBAction private func exclusiveMultipleLabelsSwitchSelected(_ sender: UISwitch) {
        PersistedOptions.exclusiveMultipleLabels = sender.isOn
        view.associatedFilter?.update(signalUpdate: .animated)
    }

    @IBAction private func autoArchiveSwitchSelected(_ sender: UISwitch) {
        if sender.isOn {
            let a = UIAlertController(title: "Are you sure?", message: "This can use a lot of data (and storage) when adding web links!\n\nActivate this only if you know what you are doing.", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Activate", style: .destructive) { _ in
                PersistedOptions.autoArchiveUrlComponents = true
            })
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak sender] _ in
                sender?.setOn(false, animated: true)
            })
            present(a, animated: true)
        } else {
            PersistedOptions.autoArchiveUrlComponents = false
        }
    }

    @IBAction private func actionSelectorValueChanged(_ sender: UISegmentedControl) {
        if let value = DefaultTapAction(rawValue: sender.selectedSegmentIndex) {
            PersistedOptions.actionOnTap = value
        }
    }

    @IBAction func searchselectorValueChanged(_: UISegmentedControl) {
        switch searchSelector.selectedSegmentIndex {
        case 0:
            PersistedOptions.useExplicitSearch = false
            PersistedOptions.inclusiveSearchTerms = false
        case 1:
            PersistedOptions.useExplicitSearch = true
            PersistedOptions.inclusiveSearchTerms = true
        case 2:
            PersistedOptions.useExplicitSearch = true
            PersistedOptions.inclusiveSearchTerms = false
        default:
            break
        }
        updateSearchSelectorDescription()
        view.associatedFilter?.update(signalUpdate: .animated)
    }

    @IBAction private func twoColumnsSwitchSelected(_ sender: UISwitch) {
        PersistedOptions.forceTwoColumnPreference = sender.isOn
        if phoneMode {
            sendNotification(name: .ItemCollectionNeedsDisplay, object: true)
        }
    }

    @IBAction private func separateItemsSwitchSelected(_ sender: UISwitch) {
        PersistedOptions.separateItemPreference = sender.isOn
    }

    @IBAction private func displayNotesInMainViewSelected(_ sender: UISwitch) {
        PersistedOptions.displayNotesInMainView = sender.isOn
        sendNotification(name: .ItemCollectionNeedsDisplay)
    }

    @IBAction private func fullScreenPreviewsSelected(_ sender: UISwitch) {
        PersistedOptions.fullScreenPreviews = sender.isOn
    }

    @IBAction private func autoConvertUrlsSelected(_ sender: UISwitch) {
        PersistedOptions.automaticallyDetectAndConvertWebLinks = sender.isOn
    }

    @IBAction private func blockGladysLinksSelected(_ sender: UISwitch) {
        PersistedOptions.blockGladysUrlRequests = sender.isOn
    }

    @IBAction private func generateLabelsFromTitleSelected(_ sender: UISwitch) {
        PersistedOptions.autoGenerateLabelsFromText = sender.isOn
    }

    @IBAction private func generateLabelsFromThumbnailSelected(_ sender: UISwitch) {
        PersistedOptions.autoGenerateLabelsFromImage = sender.isOn
    }

    @IBAction private func generateTextFromThumbnailSelected(_ sender: UISwitch) {
        PersistedOptions.autoGenerateTextFromImage = sender.isOn
    }

    @IBAction private func requestInlineDropsSelected(_ sender: UISwitch) {
        PersistedOptions.requestInlineDrops = sender.isOn
    }

    @IBAction private func transcribeSpeechInMediaSelected(_ sender: UISwitch) {
        if sender.isOn {
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    switch status {
                    case .authorized:
                        if let testRecognizer = SFSpeechRecognizer(), testRecognizer.isAvailable, testRecognizer.supportsOnDeviceRecognition {
                            PersistedOptions.transcribeSpeechFromMedia = true
                            await genericAlert(title: "Activated", message: "Please note that this feature can significantly increase the processing time of media items with long durations.")
                        } else {
                            sender.isOn = false
                            PersistedOptions.transcribeSpeechFromMedia = false
                            await genericAlert(title: "Could not activate", message: "This device does not support on-device speech recognition.")
                        }
                    case .denied, .notDetermined, .restricted:
                        sender.isOn = false
                        PersistedOptions.transcribeSpeechFromMedia = false
                    @unknown default:
                        sender.isOn = false
                        PersistedOptions.transcribeSpeechFromMedia = false
                    }
                }
            }
        } else {
            PersistedOptions.transcribeSpeechFromMedia = false
        }
    }

    @IBAction private func applyMlToUrlsSwitchSelected(_ sender: UISwitch) {
        PersistedOptions.includeUrlImagesInMlLogic = sender.isOn
    }

    @IBAction private func badgeIconSwitch(_ sender: UISwitch) {
        if !sender.isOn {
            PersistedOptions.badgeIconWithItemCount = false
            Model.updateBadge()
            return
        }

        badgeIconSwitch.isEnabled = false
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .provisional]) { granted, error in
            Task { @MainActor in
                self.badgeIconSwitch.isEnabled = true
                if granted {
                    log("Got provisional badging permission")
                    PersistedOptions.badgeIconWithItemCount = true
                    Model.updateBadge()
                } else if let error {
                    self.badgeIconSwitch.isOn = false
                    await genericAlert(title: "Error", message: "Could not obtain permission to display badges, you may need to manually allow Gladys to display badges from settings.", offerSettingsShortcut: true)
                    log("Error requesting badge permission: \(error.localizedDescription)")
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        explicitScrolling = true
        doneButtonLocation = .right

        autoConvertUrlsSwitch.isOn = PersistedOptions.automaticallyDetectAndConvertWebLinks
        blockGladysUrls.isOn = PersistedOptions.blockGladysUrlRequests
        generateLabelsFromTitlesSwitch.isOn = PersistedOptions.autoGenerateLabelsFromText
        generateLabelsFromThumbnailsSwitch.isOn = PersistedOptions.autoGenerateLabelsFromImage
        generateTextFromThumbnailsSwitch.isOn = PersistedOptions.autoGenerateTextFromImage
        transcribeSpeechInMedia.isOn = PersistedOptions.transcribeSpeechFromMedia
        applyMlToUrlsSwitch.isOn = PersistedOptions.includeUrlImagesInMlLogic
        separateItemsSwitch.isOn = PersistedOptions.separateItemPreference
        twoColumnsSwitch.isOn = PersistedOptions.forceTwoColumnPreference
        removeItemsWhenDraggedOutSwitch.isOn = PersistedOptions.removeItemsWhenDraggedOut
        dontAutoLabelNewItemsSwitch.isOn = PersistedOptions.dontAutoLabelNewItems
        displayNotesInMainViewSwitch.isOn = PersistedOptions.displayNotesInMainView
        displayLabelsInMainViewSwitch.isOn = PersistedOptions.displayLabelsInMainView
        showCopyMoveSwitchSelectorSwitch.isOn = PersistedOptions.showCopyMoveSwitchSelector
        allowLabelsInExtensionSwitch.isOn = PersistedOptions.setLabelsWhenActioning
        autoArchiveSwitch.isOn = PersistedOptions.autoArchiveUrlComponents
        exclusiveLabelsSwitch.isOn = PersistedOptions.exclusiveMultipleLabels
        wideModeSwitch.isOn = PersistedOptions.wideMode
        fullScreenSwitch.isOn = PersistedOptions.fullScreenPreviews
        badgeIconSwitch.isOn = PersistedOptions.badgeIconWithItemCount
        requestInlineDrops.isOn = PersistedOptions.requestInlineDrops

        fullScreenHolder.isHidden = UIDevice.current.userInterfaceIdiom == .phone

        actionSelector.selectedSegmentIndex = PersistedOptions.actionOnTap.rawValue

        if PersistedOptions.useExplicitSearch {
            searchSelector.selectedSegmentIndex = 0
        } else if PersistedOptions.inclusiveSearchTerms {
            searchSelector.selectedSegmentIndex = 1
        } else {
            searchSelector.selectedSegmentIndex = 2
        }
        updateSearchSelectorDescription()
    }

    func updateSearchSelectorDescription() {
        switch searchSelector.selectedSegmentIndex {
        case 0:
            searchDescription.text = "Use iOS semantic search, recommended for iOS 18 and above"
        case 1:
            searchDescription.text = "Show results that contain any of the provided words"
        case 2:
            searchDescription.text = "Only show results that contain all of the provided words"
        default:
            break
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if segue.identifier == "toSiriOptions", let p = segue.destination.popoverPresentationController {
            p.delegate = self
        }
    }

    func adaptivePresentationStyle(for _: UIPresentationController, traitCollection _: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}
