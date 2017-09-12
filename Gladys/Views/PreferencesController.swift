
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
					self.model.importData(from: url) { success in
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

	var model: Model!

	@IBOutlet weak var infoLabel: UILabel!
	@IBOutlet weak var container: UIView!
	@IBOutlet weak var innerFrame: UIView!
	@IBOutlet weak var spinner: UIActivityIndicatorView!

	@IBAction func deleteAllItemsSelected(_ sender: UIBarButtonItem) {
		let a = UIAlertController(title: "Are you sure?", message: "This will remove all current items from your collection. This cannot be undone, are you sure?", preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "Delete All", style: .destructive, handler: { [weak self] action in
			self?.deleteAllItems()
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
		present(a, animated: true)
	}

	private func deleteAllItems() {
		for item in model.drops {
			item.delete()
		}
		model.drops.removeAll()
		model.save()
		NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
	}

	@IBAction func doneSelected(_ sender: UIBarButtonItem) {
		prepareForDismiss()
		dismiss(animated: true)
	}

	private func prepareForDismiss() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
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

	@objc private func restorePurchases() {
		prepareForDismiss()
		dismiss(animated: true)
		SKPaymentQueue.default().restoreCompletedTransactions()
	}

	@objc private func externalDataUpdate() {
		spinner.stopAnimating()
		infoLabel.text = "\(model.drops.count) Items\n" + diskSizeFormatter.string(fromByteCount: model.sizeInBytes)
	}
}
