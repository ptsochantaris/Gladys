
import UIKit
import MapKit
import Contacts
import CloudKit
import QuickLook

extension ArchivedDropItemType: QLPreviewControllerDataSource {

	var dragItem: UIDragItem {
		let i = UIDragItem(itemProvider: itemProvider)
		i.localObject = self
		return i
	}

	func quickLook(extraRightButton: UIBarButtonItem?) -> UIViewController? {

		if isWebURL, let url = encodedUrl {
			let d = ViewController.shared.storyboard!.instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading..."
			d.address = url as URL
			d.relatedItem = Model.item(uuid: parentUuid)
			d.relatedChildItem = self
			d.navigationItem.rightBarButtonItem = extraRightButton
			return d

		} else if isWebArchive {
			let d = ViewController.shared.storyboard!.instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading..."
			d.webArchive = PreviewItem(typeItem: self)
			d.relatedItem = Model.item(uuid: parentUuid)
			d.relatedChildItem = self
			d.navigationItem.rightBarButtonItem = extraRightButton
			return d

		} else if canPreview {
			let q = QLPreviewController()
			q.title = oneTitle
			q.dataSource = self
			q.modalPresentationStyle = .popover
			q.navigationItem.rightBarButtonItem = extraRightButton
			q.preferredContentSize = mainWindow.bounds.size
			return q
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
		if let canPreviewCache = canPreviewCache {
			return canPreviewCache
		}
		let res = isWebArchive || QLPreviewController.canPreview(previewTempPath as NSURL)
		canPreviewCache = res
		return res
	}
}
