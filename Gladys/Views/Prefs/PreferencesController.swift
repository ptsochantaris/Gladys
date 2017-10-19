
import UIKit
import MobileCoreServices
import ZIPFoundation

final class PreferencesController : GladysViewController, UIDragInteractionDelegate, UIDropInteractionDelegate {

	private var archiveDragItems: [UIDragItem] {
		let i = NSItemProvider()
		i.suggestedName = "Gladys Archive.gladysArchive"
		i.registerFileRepresentation(forTypeIdentifier: "build.bru.gladys.archive", fileOptions: [], visibility: .all) { completion -> Progress? in

			let p = Progress(totalUnitCount: 2)

			DispatchQueue.global(qos: .userInitiated).async {

				DispatchQueue.main.async {
					self.spinner.startAnimating()
					self.infoLabel.isHidden = true
				}

				let fm = FileManager.default
				let tempPath = Model.appStorageUrl.deletingLastPathComponent().appendingPathComponent("Exported Data")
				if fm.fileExists(atPath: tempPath.path) {
					try! fm.removeItem(at: tempPath)
				}

				p.completedUnitCount += 1

				try! fm.copyItem(at: Model.appStorageUrl, to: tempPath)

				p.completedUnitCount += 1

				completion(tempPath, false, nil)
				try! fm.removeItem(at: tempPath)

				DispatchQueue.main.async {
					self.spinner.stopAnimating()
					self.infoLabel.isHidden = false
				}
			}

			return p
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

	private var zipDragItems: [UIDragItem] {
		let i = NSItemProvider()
		i.suggestedName = "Gladys.zip"
		i.registerFileRepresentation(forTypeIdentifier: kUTTypeZipArchive as String, fileOptions: [], visibility: .all) { completion -> Progress? in

			let dropsCopy = ViewController.shared.model.drops.filter { $0.loadingProgress == nil && !$0.isDeleting }
			let itemCount = Int64(1 + dropsCopy.count)
			let p = Progress(totalUnitCount: itemCount)

			DispatchQueue.global(qos: .userInitiated).async {

				DispatchQueue.main.async {
					self.zipSpinner.startAnimating()
					self.zipImage.isHidden = true
				}

				let fm = FileManager.default
				let tempPath = Model.appStorageUrl.deletingLastPathComponent().appendingPathComponent("Gladys.zip")
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

				completion(tempPath, false, nil)
				try! fm.removeItem(at: tempPath)

				DispatchQueue.main.async {
					self.zipSpinner.stopAnimating()
					self.zipImage.isHidden = false
				}
			}

			return p
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
			if typeItem.representedClass == "__NSCFString", let string = typeItem.decode() as? String, let data = string.data(using: .utf8) {
				bytes = data
			}
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
			p.loadFileRepresentation(forTypeIdentifier: "build.bru.gladys.archive") { url, error in
				if let url = url {
					let model = ViewController.shared.model
					model.importData(from: url) { success in
						DispatchQueue.main.async {
							if !success {
								genericAlert(title: "Could not import data", message: "The data transfer failed", on: self)
							}
							self.externalDataUpdate()
						}
					}
				} else {
					DispatchQueue.main.async {
						genericAlert(title: "Could not import data", message: "The data transfer failed", on: self)
						self.externalDataUpdate()
					}
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

	@IBOutlet weak var infoLabel: UILabel!
	@IBOutlet weak var container: UIView!
	@IBOutlet weak var innerFrame: UIView!
	@IBOutlet weak var spinner: UIActivityIndicatorView!

	@IBOutlet weak var zipContainer: UIView!
	@IBOutlet weak var zipInnerFrame: UIView!
	@IBOutlet weak var zipSpinner: UIActivityIndicatorView!
	@IBOutlet weak var zipImage: UIImageView!

	@IBAction func deleteAllItemsSelected(_ sender: UIBarButtonItem) {
		let a = UIAlertController(title: "Are you sure?", message: "This will remove all items from your collection. This cannot be undone.", preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "Delete All", style: .destructive, handler: { [weak self] action in
			self?.deleteAllItems()
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
		present(a, animated: true)
	}

	private func deleteAllItems() {
		ViewController.shared.model.resetEverything()
	}

	@IBAction func doneSelected(_ sender: UIBarButtonItem) {
		done()
	}

	@IBOutlet weak var versionLabel: UIBarButtonItem!
	@IBOutlet weak var deleteAll: UIBarButtonItem!

	override func viewDidLoad() {
		super.viewDidLoad()

		container.layer.cornerRadius = 10
		innerFrame.layer.cornerRadius = 5

		zipContainer.layer.cornerRadius = 10
		zipInnerFrame.layer.cornerRadius = 5

		let dragInteraction = UIDragInteraction(delegate: self)
		container.addInteraction(dragInteraction)
		let dropInteraction = UIDropInteraction(delegate: self)
		container.addInteraction(dropInteraction)

		let zipDragInteraction = UIDragInteraction(delegate: self)
		zipContainer.addInteraction(zipDragInteraction)

		let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
		let b = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		versionLabel.title = "v\(v) (\(b))"

		NotificationCenter.default.addObserver(self, selector: #selector(externalDataUpdate), name: .ExternalDataUpdated, object: nil)
		externalDataUpdate()

		container.isAccessibilityElement = true
		container.accessibilityLabel = "Import and export area"

		zipContainer.isAccessibilityElement = true
		zipContainer.accessibilityLabel = "ZIP Data"
	}

	private var firstView = true
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if firstView {
			let s = view.systemLayoutSizeFitting(CGSize(width: 320, height: 0),
			                                     withHorizontalFittingPriority: .required,
			                                     verticalFittingPriority: .fittingSizeLevel)
			preferredContentSize = s
			firstView = false
		}
	}

	private func done() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
		}
		dismiss(animated: true)
	}

	@objc private func externalDataUpdate() {
		spinner.stopAnimating()
		let model = ViewController.shared.model
		let count = model.drops.count
		if count > 0 {
			let size = diskSizeFormatter.string(fromByteCount: model.sizeInBytes)
			infoLabel.text = "\(count) Items\n\(size)"
			deleteAll.isEnabled = true
		} else {
			infoLabel.text = "No Items"
			deleteAll.isEnabled = false
		}
		container.accessibilityValue = infoLabel.text
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "showAbout" {
			if navigationItem.rightBarButtonItem == nil {
				segue.destination.navigationItem.rightBarButtonItem = nil
			}
		}
	}
}
