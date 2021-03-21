import UIKit
import MobileCoreServices
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

	private func alertOnMainThread(error: Error) {
		DispatchQueue.main.async {
			genericAlert(title: "Error", message: error.localizedDescription)
		}
	}

	private var archiveDragItems: [UIDragItem] {
        guard let filter = view.associatedFilter else { return [] }

		let i = NSItemProvider()
		i.suggestedName = "Gladys Archive.gladysArchive"
		i.registerFileRepresentation(forTypeIdentifier: GladysFileUTI, fileOptions: [], visibility: .all) { completion -> Progress? in
			DispatchQueue.main.async {
				self.showExportActivity(true)
			}
            return Model.createArchive(using: filter) { url, error in
				completion(url, false, error)
				if let url = url {
					try? FileManager.default.removeItem(at: url)
				} else if let error = error {
					self.alertOnMainThread(error: error)
				}
				DispatchQueue.main.async {
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
		i.registerFileRepresentation(forTypeIdentifier: kUTTypeZipArchive as String, fileOptions: [], visibility: .all) { completion -> Progress? in
			DispatchQueue.main.async {
				self.showZipActivity(true)
			}
            return Model.createZip(using: filter) { url, error in
				completion(url, false, error)
				if let url = url {
					try? FileManager.default.removeItem(at: url)
				} else if let error = error {
					self.alertOnMainThread(error: error)
				}
				DispatchQueue.main.async {
					self.showZipActivity(false)
				}
			}
		}
		return [UIDragItem(itemProvider: i)]
	}

	func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
		if interaction.view == container {
			return archiveDragItems
		} else if interaction.view == zipContainer {
			return zipDragItems
		} else {
			return []
		}
	}

	func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
		if let p = session.items.first?.itemProvider {
			infoLabel.text = nil
			spinner.startAnimating()
			exportOnlyVisibleSwitch.isEnabled = false
			var cancelled = false
			let progress = p.loadFileRepresentation(forTypeIdentifier: GladysFileUTI) { url, error in
				if cancelled {
					DispatchQueue.main.async {
						self.updateUI()
					}
					return
				}
				if let url = url {
					DispatchQueue.main.sync { // sync is intentional, to keep the data around
						self.importArchive(from: url)
					}
				} else {
					DispatchQueue.main.async {
						if let e = error {
							genericAlert(title: "Could not import data", message: "The data transfer failed: \(e.finalDescription)")
						} else {
							genericAlert(title: "Could not import data", message: "The data transfer failed")
						}
						self.updateUI()
					}
				}
			}
			progress.cancellationHandler = {
				cancelled = true
				DispatchQueue.main.async {
					self.updateUI()
				}
			}
		}
	}

	func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
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

	@IBAction private func deleteAllItemsSelected(_ sender: UIBarButtonItem) {
		if spinner.isAnimating || zipSpinner.isAnimating {
			return
		}

		let title: String
		let subtitle: String
		let actionName: String

		if CloudManager.syncSwitchedOn {
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

		NotificationCenter.default.addObserver(self, selector: #selector(updateUI), name: .ModelDataUpdated, object: nil)

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
    
	@objc private func updateUI() {
		spinner.stopAnimating()
		exportOnlyVisibleSwitch.isEnabled = true

        guard let filter = view.associatedFilter else { return }

		let count = filter.eligibleDropsForExport.count
		if PersistedOptions.exportOnlyVisibleItems {
			if count > 0 {
                let bytes = filter.sizeOfVisibleItemsInBytes
				let size = diskSizeFormatter.string(fromByteCount: bytes)
				if count > 1 {
					infoLabel.text = "\(count) Visible Items\n\(size)"
				} else {
					infoLabel.text = "1 Visible Item\n\(size)"
				}
			} else {
				infoLabel.text = "No Visible Items"
			}
		} else {
			if count > 0 {
				let size = diskSizeFormatter.string(fromByteCount: Model.sizeInBytes)
				if count > 1 {
					infoLabel.text = "\(count) Items\n\(size)"
				} else {
					infoLabel.text = "1 Item"
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
			self?.importSelected()
		})
		a.addAction(UIAlertAction(title: "Export to an Archive", style: .default) { [weak self] _ in
			self?.exportSelected()
		})
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
	}

	private func exportSelected() {
        guard let filter = view.associatedFilter else { return }
		DispatchQueue.main.async {
			self.showExportActivity(true)
		}
        Model.createArchive(using: filter) { url, error in
			self.completeOperation(to: url, error: error)
			DispatchQueue.main.async {
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
	    	try Model.importArchive(from: url, removingOriginal: true)
		} catch {
			alertOnMainThread(error: error)
		}
		updateUI()
	}

	private func completeOperation(to url: URL?, error: Error?) {
		if let error = error {
			alertOnMainThread(error: error)
			return
		}
		guard let url = url else { return }
		DispatchQueue.main.async {
			self.exportingFileURL = url
            let p = UIDocumentPickerViewController(forExporting: [url])
			p.delegate = self
			self.present(p, animated: true)
		}
	}

	@objc private func zipSelected() {
        guard let filter = view.associatedFilter else { return }
        
		DispatchQueue.main.async {
			self.showZipActivity(true)
		}
        Model.createZip(using: filter) { url, error in
			self.completeOperation(to: url, error: error)
			DispatchQueue.main.async {
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
			DispatchQueue.main.async {
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
