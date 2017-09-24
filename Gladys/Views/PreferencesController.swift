
import UIKit
import StoreKit

final class PreferencesController : UIViewController, UIDragInteractionDelegate, UIDropInteractionDelegate {

	func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
		let i = NSItemProvider()
		let fileName = "Gladys Archive.gladysArchive"
		i.suggestedName = fileName
		i.registerFileRepresentation(forTypeIdentifier: "build.bru.gladys.archive", fileOptions: [], visibility: .all) { completion -> Progress? in
			let fm = FileManager.default

			let tempPath = Model.appStorageUrl.deletingLastPathComponent().appendingPathComponent("Exported Data")
			if fm.fileExists(atPath: tempPath.path) {
				try! fm.removeItem(at: tempPath)
			}
			try! fm.copyItem(at: Model.appStorageUrl, to: tempPath)

			completion(tempPath, false, nil)
			try! fm.removeItem(at: tempPath)
			return nil
		}
		return [UIDragItem(itemProvider: i)]
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

	@IBAction func deleteAllItemsSelected(_ sender: UIBarButtonItem) {
		let a = UIAlertController(title: "Are you sure?", message: "This will remove all items from your collection. This cannot be undone.", preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "Delete All", style: .destructive, handler: { [weak self] action in
			self?.deleteAllItems()
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
		present(a, animated: true)
	}

	private func deleteAllItems() {
		let model = ViewController.shared.model
		for item in model.drops {
			item.delete()
		}
		model.drops.removeAll()
		model.save()
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
	}

	@IBAction func doneSelected(_ sender: UIBarButtonItem) {
		done()
	}

	@IBOutlet weak var versionLabel: UIBarButtonItem!
	@IBOutlet weak var deleteAll: UIBarButtonItem!

	@IBAction func aboutSelected(_ sender: UIBarButtonItem) {
		let u = URL(string: "https://bru.build/app/gladys")!
		UIApplication.shared.open(u, options: [:]) { success in
			if success {
				self.done()
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		container.layer.cornerRadius = 10
		innerFrame.layer.cornerRadius = 5

		let dragInteraction = UIDragInteraction(delegate: self)
		container.addInteraction(dragInteraction)
		let dropInteraction = UIDropInteraction(delegate: self)
		container.addInteraction(dropInteraction)

		let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
		let b = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		versionLabel.title = "v\(v) (\(b))"

		NotificationCenter.default.addObserver(self, selector: #selector(externalDataUpdate), name: .ExternalDataUpdated, object: nil)
		externalDataUpdate()

		if !infiniteMode {
			let spacer1 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
			let spacer2 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
			let restore = UIBarButtonItem(title: "Restore Purchases", style: .plain, target: self, action: #selector(restorePurchases))
			toolbarItems = [spacer1, restore, spacer2]
			navigationController?.toolbar.tintColor = view.tintColor
			navigationController?.isToolbarHidden = false
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		let s = view.systemLayoutSizeFitting(CGSize(width: 320, height: 0),
		                                     withHorizontalFittingPriority: .required,
		                                     verticalFittingPriority: .fittingSizeLevel)
		preferredContentSize = s
	}

	private func done() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
		}
		dismiss(animated: true)
	}

	@objc private func restorePurchases() {
		done()
		SKPaymentQueue.default().restoreCompletedTransactions()
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
	}
}
