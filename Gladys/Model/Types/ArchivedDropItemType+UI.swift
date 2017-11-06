
import UIKit
import MapKit
import Contacts
import CloudKit
import QuickLook

extension ArchivedDropItemType: QLPreviewControllerDataSource {

	var dragItem: UIDragItem {

		let p = NSItemProvider()
		p.suggestedName = oneTitle
		register(with: p)

		let i = UIDragItem(itemProvider: p)
		i.localObject = self
		return i
	}

	var dataExists: Bool {
		return FileManager.default.fileExists(atPath: bytesPath.path)
	}

	var backgroundInfoObject: (Any?, Int) {
		switch representedClass {
		case "MKMapItem": return (decode() as? MKMapItem, 30)
		case "UIColor": return (decode() as? UIColor, 10)
		default: return (nil, 0)
		}
	}

	var itemForShare: (Any?, Int) {

		if typeIdentifier == "public.vcard", let bytes = bytes, let contact = (try? CNContactVCardSerialization.contacts(with: bytes))?.first {
			return (contact, 12)
		}

		if typeIdentifier == "com.apple.mapkit.map-item", let item = decode() as? MKMapItem {
			return (item, 15)
		}

		if let url = encodedUrl {

			if representedClass == "URL" {
				return (url, 10)
			}

			if typeIdentifier == "public.url" {
				return (url, 5)
			}

			return (url, 3)
		}

		return (bytes, 0)
	}

	var sizeDescription: String? {
		return diskSizeFormatter.string(fromByteCount: sizeInBytes)
	}

	//////////////////////////////////////////////////////// quicklook

	func quickLook(extraRightButton: UIBarButtonItem?) -> UIViewController? {

		if QLPreviewController.canPreview(previewTempPath as NSURL) {
			let q = QLPreviewController()
			q.title = oneTitle
			q.dataSource = self
			q.modalPresentationStyle = .popover
			q.navigationItem.rightBarButtonItem = extraRightButton
			if let s = UIApplication.shared.windows.first?.bounds.size {
				q.preferredContentSize = s
			}
			return q

		} else if let url = encodedUrl {
			let d = ViewController.shared.storyboard!.instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading..."
			d.address = url as URL
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

	private class PreviewItem: NSObject, QLPreviewItem {
		let previewItemURL: URL?
		let previewItemTitle: String?
		let needsCleanup: Bool

		init(typeItem: ArchivedDropItemType) {

			let blobPath = typeItem.bytesPath
			let tempPath = typeItem.previewTempPath

			if blobPath == tempPath {
				previewItemURL = blobPath
				needsCleanup = false
			} else {
				let fm = FileManager.default
				if fm.fileExists(atPath: tempPath.path) {
					try? fm.removeItem(at: tempPath)
				}

				if let data = typeItem.dataForWrappedItem {
					try? data.write(to: tempPath)
				} else {
					try? fm.copyItem(at: blobPath, to: tempPath)
				}
				log("Created temporary file for preview")
				previewItemURL = tempPath
				needsCleanup = true
			}

			previewItemTitle = typeItem.oneTitle
		}

		deinit {
			if needsCleanup, let previewItemURL = previewItemURL {
				let fm = FileManager.default
				if fm.fileExists(atPath: previewItemURL.path) {
					try? fm.removeItem(at: previewItemURL)
					log("Removed temporary file for preview")
				}
			}
		}
	}

	var canPreview: Bool {
		if QLPreviewController.canPreview(previewTempPath as NSURL) {
			return true
		} else if let url = encodedUrl, url.scheme?.hasPrefix("http") ?? false {
			return true
		} else {
			return false
		}
	}

	var previewTempPath: URL {
		if let f = fileExtension {
			return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gladys-preview-blob", isDirectory: false).appendingPathExtension(f)
		} else {
			return bytesPath
		}
	}
}
