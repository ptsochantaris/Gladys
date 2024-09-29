import GladysCommon
import GladysUI
import GladysUIKit
import UIKit
import UniformTypeIdentifiers

final class PreferencesController: GladysViewController, UIDragInteractionDelegate, UIDropInteractionDelegate, UIDocumentPickerDelegate {
    @IBOutlet private var exportOnlyVisibleSwitch: UISwitch!

    var associatedFilter: Filter?

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
        guard let filter = associatedFilter else { return [] }

        let i = NSItemProvider()
        i.suggestedName = "Gladys Archive.gladysArchive"
        i.registerFileRepresentation(forTypeIdentifier: GladysFileUTI, fileOptions: [], visibility: .all) { completion -> Progress? in
            let p = Progress(totalUnitCount: 100)
            Task { @MainActor in
                self.showExportActivity(true)
                do {
                    let url = try await ImportExport.createArchive(using: filter, progress: p)
                    completion(url, false, nil)
                    try? FileManager.default.removeItem(at: url)
                } catch {
                    completion(nil, false, error)
                    await genericAlert(title: "Error", message: error.localizedDescription)
                }
                self.showExportActivity(false)
            }
            return p
        }
        return [UIDragItem(itemProvider: i)]
    }

    private var zipDragItems: [UIDragItem] {
        guard let filter = associatedFilter else { return [] }

        let i = NSItemProvider()
        i.suggestedName = "Gladys.zip"
        i.registerFileRepresentation(forTypeIdentifier: UTType.zip.identifier, fileOptions: [], visibility: .all) { completion -> Progress? in
            let p = Progress(totalUnitCount: 100)
            Task { @MainActor in
                self.showZipActivity(true)
                do {
                    let url = try await ImportExport.createZip(using: filter, progress: p)
                    completion(url, false, nil)
                    try? FileManager.default.removeItem(at: url)
                } catch {
                    completion(nil, false, error)
                    await genericAlert(title: "Error", message: error.localizedDescription)
                }
                self.showZipActivity(false)
            }
            return p
        }
        return [UIDragItem(itemProvider: i)]
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning _: UIDragSession) -> [UIDragItem] {
        if interaction.view == container {
            archiveDragItems
        } else if interaction.view == zipContainer {
            zipDragItems
        } else {
            []
        }
    }

    func dropInteraction(_: UIDropInteraction, performDrop session: UIDropSession) {
        if let p = session.items.first?.itemProvider {
            infoLabel.text = nil
            spinner.startAnimating()
            exportOnlyVisibleSwitch.isEnabled = false
            var cancelled = false
            let progress = p.loadFileRepresentation(forTypeIdentifier: GladysFileUTI) { url, error in
                if onlyOnMainThread({ cancelled }) {
                    Task {
                        await self.updateUI()
                    }
                    return
                }
                if let url {
                    let securityScoped = url.startAccessingSecurityScopedResource()
                    Task {
                        await self.importArchive(from: url)
                        if securityScoped {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                } else {
                    Task {
                        if let error {
                            await genericAlert(title: "Could not import data", message: "The data transfer failed: \(error.localizedDescription)")
                        } else {
                            await genericAlert(title: "Could not import data", message: "The data transfer failed")
                        }
                        await self.updateUI()
                    }
                }
            }
            progress.cancellationHandler = {
                onlyOnMainThread {
                    cancelled = true
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

        associatedFilter = view.associatedFilter
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

        notifications(for: .ModelDataUpdated) { [weak self] _ in
            self?.updateUI()
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

        guard let filter = associatedFilter else { return }

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
        a.addAction(UIAlertAction(title: "Import from an Archive", style: .default) { [weak self] _ in
            guard let self else { return }
            importSelected()
        })
        a.addAction(UIAlertAction(title: "Export to an Archive", style: .default) { [weak self] _ in
            guard let self else { return }
            exportSelected()
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(a, animated: true)
    }

    private func exportSelected() {
        guard let filter = associatedFilter else { return }
        showExportActivity(true)
        Task {
            do {
                let url = try await ImportExport.createArchive(using: filter, progress: Progress())
                completeOperation(url: url)
            } catch {
                await genericAlert(title: "Error", message: error.localizedDescription)
            }
            showExportActivity(false)
        }
    }

    private func importSelected() {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(GladysFileUTI)!])
        p.delegate = self
        present(p, animated: true)
    }

    private func importArchive(from url: URL) async {
        do {
            try await ImportExport.importArchive(from: url, removingOriginal: true)
        } catch {
            await genericAlert(title: "Error", message: error.localizedDescription)
        }
        updateUI()
    }

    private func completeOperation(url: URL) {
        exportingFileURL = url
        let p = UIDocumentPickerViewController(forExporting: [url])
        p.delegate = self
        present(p, animated: true)
    }

    @objc private func zipSelected() {
        guard let filter = associatedFilter else { return }
        showZipActivity(true)
        Task {
            do {
                let url = try await ImportExport.createZip(using: filter, progress: Progress())
                completeOperation(url: url)
            } catch {
                await genericAlert(title: "Error", message: error.localizedDescription)
            }
            self.showZipActivity(false)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if exportingFileURL != nil {
            manualExportDone()

        } else {
            infoLabel.text = nil
            spinner.startAnimating()
            exportOnlyVisibleSwitch.isEnabled = false

            let url = urls.first!
            let securityScoped = url.startAccessingSecurityScopedResource()
            Task {
                await importArchive(from: url)
                if securityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
        controller.dismiss(animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        manualExportDone()
        controller.dismiss(animated: true)
    }

    private func manualExportDone() {
        if let e = exportingFileURL {
            Task {
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
