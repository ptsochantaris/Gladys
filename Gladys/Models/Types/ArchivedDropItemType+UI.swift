
import UIKit
import MapKit
import Contacts
import CloudKit
import QuickLook

extension ArchivedDropItemType: QLPreviewControllerDataSource {

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

		if isWebURL, let url = encodedUrl {
			let d = ViewController.shared.storyboard!.instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading..."
			d.address = url as URL
			d.navigationItem.rightBarButtonItem = extraRightButton
			return d

		} else if QLPreviewController.canPreview(previewTempPath as NSURL) {
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
		}
		
		return nil
	}

	func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
		return 1
	}

	func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
		return PreviewItem(typeItem: self)
	}

	var canPreview: Bool {
		return isWebArchive || QLPreviewController.canPreview(previewTempPath as NSURL)
	}
}
