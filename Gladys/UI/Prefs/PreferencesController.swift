import GladysCommon
import GladysUI
import Minions
import UIKit
import UniformTypeIdentifiers

final class PreferencesController: GladysViewController, UIDragInteractionDelegate, UIDropInteractionDelegate, UIDocumentPickerDelegate {
    @IBOutlet private var exportOnlyVisibleSwitch: UISwitch!

    private func showExportActivity(_ show: Bool) {
        if show {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        exportOnlyVisibleSwitch.isEnabled = !show
        infoLabel.isHidden = show
    }

    private func showZipActivity(_ show: Bool) {
        if show {
            zipSpinner.startAnimating()

        } else {
            zipSpinner.stopAnimating()
        }
        exportOnlyVisibleSwitch.isEnabled = !show
        zipImage.isHidden = show
    }

    private var archiveDragItems: [UIDragItem] {
        guard let filter = view.associatedFilter else { return [] }

        let i = NSItemProvider()
        i.suggestedName = "Gladys Archive.gladysArchive"
        i.registerFileRepresentation(forTypeIdentifier: GladysFileUTI, fileOptions: [], visibility: .all) { completion -> Progress? in
            Task { @MainActor in
                self.showExportActivity(true)
            }
            return ImportExport().createArchive(using: filter) { result in
                switch result {
                case let .success(url):
                    completion(url, false, nil)
                    try? FileManager.default.removeItem(at: url)
                case let .failure(error):
                    completion(nil, false, error)
                    Task {
                        await genericAlert(title: "Error", message: error.localizedDescription)
                    }
                }
                Task { @MainActor in
                    self.showExportActivity(false)
                }
            }
        }
        return [UIDragItem(itemProvider: i)]
    }

    private var zipDragItems: [UIDragItem] {
        guard let filter = view.associatedFilter else { return [] }

        let i = NSItemProvider()
        i.suggestedName = "Gladys.zip"
        i.registerFileRepresentation(forTypeIdentifier: UTType.zip.identifier, fileOptions: [], visibility: .all) { completion -> Progress? in
            Task { @MainActor in
                self.showZipActivity(true)
            }
            return ImportExport().createZip(using: filter) { result in
                switch result {
                case let .success(url):
                    completion(url, false, nil)
                    try? FileManager.default.removeItem(at: url)
                case let .failure(error):
                    completion(nil, false, error)
                    Task { @MainActor in
                        await genericAlert(title: "Error", message: error.localizedDescription)
                    }
                }
                Task { @MainActor in
                    self.showZipActivity(false)
                }
            }
        }
        return [UIDragItem(itemProvider: i)]
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning _: UIDragSession) -> [UIDragItem] {
        if interaction.view == container {
            return archiveDragItems
        } else if interaction.view == zipContainer {
            return zipDragItems
        } else {
            return []
        }
    }

    func dropInteraction(_: UIDropInteraction, performDrop session: UIDropSession) {
        if let p = session.items.first?.itemProvider {
            infoLabel.text = nil
            spinner.startAnimating()
            exportOnlyVisibleSwitch.isEnabled = false
            var cancelled = false
            let progress = p.loadFileRepresentation(forTypeIdentifier: GladysFileUTI) { url, error in
                if cancelled {
                    Task { @MainActor in
                        self.updateUI()
                    }
                    return
                }
                if let url {
                    DispatchQueue.main.sync { // sync is intentional, to keep the data around
                        self.importArchive(from: url)
                    }
                } else {
                    Task { @MainActor in
                        if let error {
                            await genericAlert(title: "Could not import data", message: "The data transfer failed: \(error.localizedDescription)")
                        } else {
                            await genericAlert(title: "Could not import data", message: "The data transfer failed")
                        }
                        self.updateUI()
                    }
                }
            }
            progress.cancellationHandler = {
                cancelled = true
                Task { @MainActor in
                    self.updateUI()
                }
            }
        }
    }

    func dropInteraction(_: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        if session.localDragSession != nil {
            return UIDropProposal(operation: UIDropOperation.cancel)
        }
        if let item = session.items.first, item.itemProvider.hasItemConformingToTypeIdentifier(GladysFileUTI) {
            return UIDropProposal(operation: UIDropOperation.copy)
        }
        return UIDropProposal(operation: UIDropOperation.forbidden)
    }

    //////////////////////////////////

    @IBOutlet private var topLabel: UILabel!
    @IBOutlet private var bottomLabel: UILabel!
    @IBOutlet private var zipLabel: UILabel!

    @IBOutlet private var infoLabel: UILabel!
    @IBOutlet private var container: UIView!
    @IBOutlet private var innerFrame: UIView!
    @IBOutlet private var spinner: UIActivityIndicatorView!

    @IBOutlet private var zipContainer: UIView!
    @IBOutlet private var zipInnerFrame: UIView!
    @IBOutlet private var zipSpinner: UIActivityIndicatorView!
    @IBOutlet private var zipImage: UIImageView!

    @IBAction private func deleteAllItemsSelected(_: UIBarButtonItem) {
        if spinner.isAnimating || zipSpinner.isAnimating {
            return
        }

        Task {
            let title: String
            let subtitle: String
            let actionName: String
            if await CloudManager.syncSwitchedOn {
                title = "Remove from all devices?"
                subtitle = "Sync is switched on, so this action will remove all your own items from all synced devices. This cannot be undone."
                actionName = "Delete From All Devices"
            } else {
                title = "Are you sure?"
                subtitle = "This will remove all your own items. This cannot be undone."
                actionName = "Delete All"
            }

            let a = UIAlertController(title: title, message: subtitle, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: actionName, style: .destructive) { _ in
                Model.resetEverything()
            })
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(a, animated: true)
        }
    }

    @IBOutlet private var deleteAll: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()

        doneButtonLocation = .right

        container.layer.cornerRadius = 10
        innerFrame.layer.cornerRadius = 5

        zipContainer.layer.cornerRadius = 10
        zipInnerFrame.layer.cornerRadius = 5

        exportOnlyVisibleSwitch.onTintColor = view.tintColor
        exportOnlyVisibleSwitch.tintColor = UIColor.g_colorLightGray
        exportOnlyVisibleSwitch.isOn = PersistedOptions.exportOnlyVisibleItems

        let dragInteraction = UIDragInteraction(delegate: self)
        container.addInteraction(dragInteraction)
        let dropInteraction = UIDropInteraction(delegate: self)
        container.addInteraction(dropInteraction)

        let zipDragInteraction = UIDragInteraction(delegate: self)
        zipContainer.addInteraction(zipDragInteraction)

        #notifications(for: .ModelDataUpdated) { _ in
            updateUI()
            return true
        }

        container.isAccessibilityElement = true
        container.accessibilityLabel = "Import and export area"

        zipContainer.isAccessibilityElement = true
        zipContainer.accessibilityLabel = "ZIP Data"

        if !dragInteraction.isEnabled { // System cannot do drag and drop
            topLabel.isHidden = true
            bottomLabel.text = "Export or import your items from/to an archive."
            zipLabel.text = "Save a ZIP file with your items."

            let importExportButton = UIButton()
            importExportButton.addTarget(self, action: #selector(importExportSelected), for: .touchUpInside)
            container.cover(with: importExportButton)

            let zipButton = UIButton()
            zipButton.addTarget(self, action: #selector(zipSelected), for: .touchUpInside)
            zipContainer.cover(with: zipButton)
        }
    }

    override func movedToWindow() {
        super.movedToWindow()
        updateUI()
    }

    private func updateUI() {
        spinner.stopAnimating()
        exportOnlyVisibleSwitch.isEnabled = true

        guard let filter = view.associatedFilter else { return }

        let count = filter.eligibleDropsForExport.count
        infoLabel.text = "…"
        if PersistedOptions.exportOnlyVisibleItems {
            if count > 0 {
                Task {
                    let bytes = await filter.sizeOfVisibleItemsInBytes()
                    let size = diskSizeFormatter.string(fromByteCount: bytes)
                    if count > 1 {
                        infoLabel.text = "\(count) Visible Items\n\(size)"
                    } else {
                        infoLabel.text = "1 Visible Item\n\(size)"
                    }
                }
            } else {
                infoLabel.text = "No Visible Items"
            }

        } else {
            if count > 0 {
                Task {
                    let bytes = await filter.sizeOfVisibleItemsInBytes()
                    let size = diskSizeFormatter.string(fromByteCount: bytes)
                    if count > 1 {
                        infoLabel.text = "\(count) Items\n\(size)"
                    } else {
                        infoLabel.text = "1 Item\n\(size)"
                    }
                }
            } else {
                infoLabel.text = "No Items"
            }
        }
        deleteAll.isEnabled = count > 0
        container.accessibilityValue = infoLabel.text
    }

    ///////////////////////////////////

    private var exportingFileURL: URL?

    @objc private func importExportSelected() {
        let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "Import from an Archive", style: .default, handler: #weakSelf { _ in
            importSelected()
        }))
        a.addAction(UIAlertAction(title: "Export to an Archive", style: .default, handler: #weakSelf { _ in
            exportSelected()
        }))
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(a, animated: true)
    }

    private func exportSelected() {
        guard let filter = view.associatedFilter else { return }
        Task { @MainActor in
            self.showExportActivity(true)
        }
        _ = ImportExport().createArchive(using: filter) { result in
            self.completeOperation(result: result)
            Task { @MainActor in
                self.showExportActivity(false)
            }
        }
    }

    private func importSelected() {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(GladysFileUTI)!])
        p.delegate = self
        present(p, animated: true)
    }

    private func importArchive(from url: URL) {
        do {
            try ImportExport().importArchive(from: url, removingOriginal: true)
        } catch {
            Task { @MainActor in
                await genericAlert(title: "Error", message: error.localizedDescription)
            }
        }
        updateUI()
    }

    private func completeOperation(result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            Task { @MainActor in
                self.exportingFileURL = url
                let p = UIDocumentPickerViewController(forExporting: [url])
                p.delegate = self
                self.present(p, animated: true)
            }
        case let .failure(error):
            Task {
                await genericAlert(title: "Error", message: error.localizedDescription)
            }
        }
    }

    @objc private func zipSelected() {
        guard let filter = view.associatedFilter else { return }

        Task { @MainActor in
            self.showZipActivity(true)
        }
        _ = ImportExport().createZip(using: filter) { result in
            self.completeOperation(result: result)
            Task { @MainActor in
                self.showZipActivity(false)
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if exportingFileURL != nil {
            manualExportDone()
        } else {
            infoLabel.text = nil
            spinner.startAnimating()
            exportOnlyVisibleSwitch.isEnabled = false
            importArchive(from: urls.first!)
        }
        controller.dismiss(animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        manualExportDone()
        controller.dismiss(animated: true)
    }

    private func manualExportDone() {
        if let e = exportingFileURL {
            Task { @MainActor in
                try? FileManager.default.removeItem(at: e)
            }
            exportingFileURL = nil
        }
    }

    /////////////////////////////

    @IBAction private func exportOnlyVisibleChanged(_ sender: UISwitch) {
        PersistedOptions.exportOnlyVisibleItems = sender.isOn
        updateUI()
    }
}
