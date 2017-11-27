
import UIKit
import MobileCoreServices
import ZIPFoundation

final class PreferencesController : GladysViewController, UIDragInteractionDelegate, UIDropInteractionDelegate, UIDocumentPickerDelegate {

	@IBOutlet weak var exportOnlyVisibleSwitch: UISwitch!

	@discardableResult
	private func createArchive(completion: @escaping (URL)->Void) -> Progress {
		let eligibleItems = eligibleDropsForExport
		let count = 2 + eligibleItems.count
		let p = Progress(totalUnitCount: Int64(count))

		DispatchQueue.main.async {
			self.spinner.startAnimating()
			self.exportOnlyVisibleSwitch.isEnabled = false
			self.infoLabel.isHidden = true
		}

		DispatchQueue.global(qos: .userInitiated).async {

			let fm = FileManager.default
			let tempPath = Model.appStorageUrl.deletingLastPathComponent().appendingPathComponent("Gladys Archive.gladysArchive")
			if fm.fileExists(atPath: tempPath.path) {
				try! fm.removeItem(at: tempPath)
			}

			p.completedUnitCount += 1

			try! fm.createDirectory(at: tempPath, withIntermediateDirectories: true, attributes: nil)
			for item in eligibleItems {
				let uuidString = item.uuid.uuidString
				let sourceForItem = Model.appStorageUrl.appendingPathComponent(uuidString)
				let desinationForItem = tempPath.appendingPathComponent(uuidString)
				try! fm.copyItem(at: sourceForItem, to: desinationForItem)
				p.completedUnitCount += 1
			}

			let data = try! JSONEncoder().encode(eligibleItems)
			try! data.write(to: tempPath.appendingPathComponent("items.json"))
			p.completedUnitCount += 1

			completion(tempPath)

			DispatchQueue.main.async {
				self.spinner.stopAnimating()
				self.exportOnlyVisibleSwitch.isEnabled = true
				self.infoLabel.isHidden = false
			}
		}

		return p
	}

	private var archiveDragItems: [UIDragItem] {
		let i = NSItemProvider()
		i.suggestedName = "Gladys Archive.gladysArchive"
		i.registerFileRepresentation(forTypeIdentifier: "build.bru.gladys.archive", fileOptions: [], visibility: .all) { completion -> Progress? in
			return self.createArchive { url in
				completion(url, false, nil)
				try! FileManager.default.removeItem(at: url)
			}
		}
		return [UIDragItem(itemProvider: i)]
	}

	private func makeLink(_ url: URL) -> String {
		return "[InternetShortcut]\r\nURL=\(url.absoluteString)\r\n"
	}

	private func truncate(string: String, limit: Int) -> String {
		if string.count > limit {
			let s = string.startIndex
			let e = string.index(string.startIndex, offsetBy: limit)
			return String(string[s..<e])
		}
		return string
	}

	private var eligibleDropsForExport: [ArchivedDropItem] {
		let items = PersistedOptions.exportOnlyVisibleItems ? Model.threadSafeFilteredDrops : Model.threadSafeDrops
		return items.filter { $0.goodToSave }
	}

	@discardableResult
	private func createZip(completion: @escaping (URL)->Void) -> Progress {

		DispatchQueue.main.async {
			self.zipSpinner.startAnimating()
			self.exportOnlyVisibleSwitch.isEnabled = false
			self.zipImage.isHidden = true
		}

		let dropsCopy = eligibleDropsForExport
		let itemCount = Int64(1 + dropsCopy.count)
		let p = Progress(totalUnitCount: itemCount)

		let tempPath = Model.appStorageUrl.deletingLastPathComponent().appendingPathComponent("Gladys.zip")

		DispatchQueue.global(qos: .userInitiated).async {

			let fm = FileManager.default
			if fm.fileExists(atPath: tempPath.path) {
				try! fm.removeItem(at: tempPath)
			}

			p.completedUnitCount += 1

			if let archive = Archive(url: tempPath, accessMode: .create) {
				for item in dropsCopy {
					var dir = item.oneTitle
					if let url = URL(string: dir) {
						if let host = url.host {
							dir = host + "-" + url.path.split(separator: "/").joined(separator: "-")
						} else {
							dir = url.path.split(separator: "/").joined(separator: "-")
						}
					} else {
						dir = dir.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "/", with: "-")
					}
					if item.typeItems.count == 1 {
						let typeItem = item.typeItems.first!
						self.addItem(typeItem, directory: nil, name: dir, in: archive)

					} else {
						for typeItem in item.typeItems {
							let d = typeItem.typeDescription ?? typeItem.filenameTypeIdentifier
							self.addItem(typeItem, directory: dir, name: d, in: archive)
						}
					}
					p.completedUnitCount += 1
				}
			}

			completion(tempPath)

			DispatchQueue.main.async {
				self.zipSpinner.stopAnimating()
				self.exportOnlyVisibleSwitch.isEnabled = true
				self.zipImage.isHidden = false
			}

		}

		return p
	}

	private var zipDragItems: [UIDragItem] {
		let i = NSItemProvider()
		i.suggestedName = "Gladys.zip"
		i.registerFileRepresentation(forTypeIdentifier: kUTTypeZipArchive as String, fileOptions: [], visibility: .all) { completion -> Progress? in
			return self.createZip { url in
				completion(url, false, nil)
				try! FileManager.default.removeItem(at: url)
			}
		}
		return [UIDragItem(itemProvider: i)]
	}

	private func addItem(_ typeItem: ArchivedDropItemType, directory: String?, name: String, in archive: Archive) {

		var bytes: Data?
		if typeItem.typeIdentifier == "public.url",
			let url = typeItem.encodedUrl,
			let data = makeLink(url as URL).data(using: .utf8) {

			bytes = data

		} else if typeItem.classWasWrapped {
			bytes = typeItem.dataForWrappedItem ?? typeItem.bytes
		}
		if let B = bytes ?? typeItem.bytes {

			var name = name
			if let ext = typeItem.fileExtension {
				name = truncate(string: name, limit: 255 - (ext.count+1)) + "." + ext
			} else {
				name = truncate(string: name, limit: 255)
			}

			if let directory = directory {
				let directory = truncate(string: directory, limit: 255)
				name = directory + "/" + name
			}

			// for now, remove in a few weeks
			name = name.replacingOccurrences(of: "\0", with: "")

			try? archive.addEntry(with: name, type: .file, uncompressedSize: UInt32(B.count)) { pos, size -> Data in
				return B[pos ..< pos+size]
			}
		}
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
			let progress = p.loadFileRepresentation(forTypeIdentifier: "build.bru.gladys.archive") { url, error in
				if cancelled {
					DispatchQueue.main.async {
						self.updateUI()
					}
					return
				}
				if let url = url {
					self.importArchive(from: url)
				} else {
					DispatchQueue.main.async {
						if let e = error {
							genericAlert(title: "Could not import data", message: "The data transfer failed: \(e.finalDescription)", on: self)
						} else {
							genericAlert(title: "Could not import data", message: "The data transfer failed", on: self)
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
		if let item = session.items.first, item.itemProvider.hasItemConformingToTypeIdentifier("build.bru.gladys.archive") {
			return UIDropProposal(operation: UIDropOperation.copy)
		}
		return UIDropProposal(operation: UIDropOperation.forbidden)
	}

	//////////////////////////////////

	@IBOutlet weak var topLabel: UILabel!
	@IBOutlet weak var bottomLabel: UILabel!
	@IBOutlet weak var zipLabel: UILabel!

	@IBOutlet weak var infoLabel: UILabel!
	@IBOutlet weak var container: UIView!
	@IBOutlet weak var innerFrame: UIView!
	@IBOutlet weak var spinner: UIActivityIndicatorView!

	@IBOutlet weak var zipContainer: UIView!
	@IBOutlet weak var zipInnerFrame: UIView!
	@IBOutlet weak var zipSpinner: UIActivityIndicatorView!
	@IBOutlet weak var zipImage: UIImageView!

	@IBAction func deleteAllItemsSelected(_ sender: UIBarButtonItem) {
		if spinner.isAnimating || zipSpinner.isAnimating {
			return
		}

		let title: String
		let subtitle: String
		let actionName: String

		if CloudManager.syncSwitchedOn {
			title = "Remove from all devices?"
			subtitle = "Sync is switched on, so this action will remove your entire collection from all synced devices. This cannot be undone."
			actionName = "Delete From All Devices"
		} else {
			title = "Are you sure?"
			subtitle = "This will remove all items from your collection. This cannot be undone."
			actionName = "Delete All"
		}

		let a = UIAlertController(title: title, message: subtitle, preferredStyle: .alert)
		a.addAction(UIAlertAction(title: actionName, style: .destructive, handler: { action in
			Model.resetEverything()
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
		present(a, animated: true)
	}

	@IBOutlet weak var deleteAll: UIBarButtonItem!

	override func viewDidLoad() {
		super.viewDidLoad()

		doneLocation = .right

		container.layer.cornerRadius = 10
		innerFrame.layer.cornerRadius = 5

		zipContainer.layer.cornerRadius = 10
		zipInnerFrame.layer.cornerRadius = 5

		exportOnlyVisibleSwitch.onTintColor = view.tintColor
		exportOnlyVisibleSwitch.tintColor = .lightGray
		exportOnlyVisibleSwitch.isOn = PersistedOptions.exportOnlyVisibleItems

		let dragInteraction = UIDragInteraction(delegate: self)
		container.addInteraction(dragInteraction)
		let dropInteraction = UIDropInteraction(delegate: self)
		container.addInteraction(dropInteraction)

		let zipDragInteraction = UIDragInteraction(delegate: self)
		zipContainer.addInteraction(zipDragInteraction)

		NotificationCenter.default.addObserver(self, selector: #selector(updateUI), name: .ExternalDataUpdated, object: nil)
		updateUI()

		container.isAccessibilityElement = true
		container.accessibilityLabel = "Import and export area"

		zipContainer.isAccessibilityElement = true
		zipContainer.accessibilityLabel = "ZIP Data"

		if !dragInteraction.isEnabled { // System cannot do drag and drop
			topLabel.isHidden = true
			bottomLabel.text = "Export or import all your items from/to an archive."
			zipLabel.text = "Save a ZIP file with all your items."

			let importExportButton = UIButton()
			importExportButton.addTarget(self, action: #selector(importExportSelected), for: .touchUpInside)
			container.cover(with: importExportButton)

			let zipButton = UIButton()
			zipButton.addTarget(self, action: #selector(zipSelected), for: .touchUpInside)
			zipContainer.cover(with: zipButton)
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@objc private func updateUI() {
		spinner.stopAnimating()
		exportOnlyVisibleSwitch.isEnabled = true
		let count = eligibleDropsForExport.count
		if PersistedOptions.exportOnlyVisibleItems {
			if count > 0 {
				let size = diskSizeFormatter.string(fromByteCount: Model.sizeOfVisibleItemsInBytes)
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
		a.addAction(UIAlertAction(title: "Import from an Archive", style: .default, handler: { action in
			self.importSelected()
		}))
		a.addAction(UIAlertAction(title: "Export to an Archive", style: .default, handler: { action in
			self.exportSelected()
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
	}

	private func exportSelected() {
		createArchive { url in
			self.export(to: url)
		}
	}

	private func importSelected() {
		let p = UIDocumentPickerViewController(documentTypes: ["build.bru.gladys.archive"], in: .import)
		p.delegate = self
		present(p, animated: true)
	}

	private func importArchive(from url: URL) {
	    Model.importData(from: url) { success in
			DispatchQueue.main.async {
				if !success {
					genericAlert(title: "Could not import data", message: "Contents were corrupted", on: self)
				}
				self.updateUI()
			}
		}
	}

	private func export(to url: URL) {
		DispatchQueue.main.async {
			self.exportingFileURL = url
			let p = UIDocumentPickerViewController(url: url, in: .exportToService)
			p.delegate = self
			self.present(p, animated: true)
		}
	}

	@objc private func zipSelected() {
		createZip { url in
			self.export(to: url)
		}
	}

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
		if exportingFileURL != nil {
			manualExportDone()
		} else {
			infoLabel.text = nil
			spinner.startAnimating()
			exportOnlyVisibleSwitch.isEnabled = false
			DispatchQueue.global(qos: .userInitiated).async {
				self.importArchive(from: urls.first!)
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
			DispatchQueue.main.async {
				try? FileManager.default.removeItem(at: e)
			}
			exportingFileURL = nil
		}
	}

	/////////////////////////////

	@IBAction func exportOnlyVisibleChanged(_ sender: UISwitch) {
		PersistedOptions.exportOnlyVisibleItems = sender.isOn
		updateUI()
	}

}
