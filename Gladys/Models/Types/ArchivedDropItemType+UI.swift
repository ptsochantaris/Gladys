
import UIKit
import MapKit
import Contacts
import CloudKit
import QuickLook

extension ArchivedDropItemType {

	private var itemProvider: NSItemProvider {
		let p = NSItemProvider()
		p.suggestedName = oneTitle
		register(with: p)
		return p
	}

	var dragItem: UIDragItem {
		let i = UIDragItem(itemProvider: itemProvider)
		i.localObject = self
		return i
	}

	func copyToPasteboard() {
		UIPasteboard.general.setItemProviders([itemProvider], localOnly: false, expirationDate: nil)
	}

	func quickLook(extraRightButton: UIBarButtonItem?) -> UIViewController? {

		if QLPreviewController.canPreview(previewTempPath as NSURL) {
			let q = QLPreviewController()
			q.title = oneTitle
			q.dataSource = self
			q.modalPresentationStyle = .popover
			q.navigationItem.rightBarButtonItem = extraRightButton
			q.preferredContentSize = mainWindow.bounds.size
			return q

		} else if isWebArchive {
			let d = ViewController.shared.storyboard!.instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading..."
			d.webArchive = PreviewItem(typeItem: self)
			d.navigationItem.rightBarButtonItem = extraRightButton
			return d

		} else if let url = encodedUrl {
			let d = ViewController.shared.storyboard!.instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading..."
			d.address = url as URL
			d.navigationItem.rightBarButtonItem = extraRightButton
			return d
		}
		return nil
	}
}
