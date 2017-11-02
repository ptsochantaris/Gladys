
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

	func register(with provider: NSItemProvider) {
		provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion -> Progress? in
			let p = Progress(totalUnitCount: 1)
			p.completedUnitCount = 1
			DispatchQueue.global(qos: .userInitiated).async {
				log("Responding with data block")
				completion(self.bytes, nil)
			}
			return p
		}
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

	func quickLook(extraRightButton: UIBarButtonItem?) -> QLPreviewController {
		let q = QLPreviewController()
		q.title = oneTitle
		q.dataSource = self
		q.modalPresentationStyle = .popover
		q.navigationItem.rightBarButtonItem = extraRightButton
		if let s = UIApplication.shared.windows.first?.bounds.size {
			q.preferredContentSize = s
		}
		return q
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

		private let item: ArchivedDropItemType

		init(typeItem: ArchivedDropItemType) {

			item = typeItem
			let blobPath = typeItem.bytesPath
			let tempPath = typeItem.previewTempPath

			if blobPath == tempPath {
				previewItemURL = blobPath
			} else {
				let fm = FileManager.default
				if fm.fileExists(atPath: tempPath.path) {
					try? fm.removeItem(at: tempPath)
				}
				try? fm.copyItem(at: blobPath, to: tempPath)
				log("Created temporary file for preview")
				previewItemURL = tempPath
			}

			previewItemTitle = typeItem.oneTitle
		}

		deinit {
			let tempPath = item.previewTempPath
			let fm = FileManager.default
			if fm.fileExists(atPath: tempPath.path) {
				try? fm.removeItem(at: tempPath)
				log("Removed temporary file for preview")
			}
		}
	}

	var canPreview: Bool {
		return QLPreviewController.canPreview(previewTempPath as NSURL)
	}

	var previewTempPath: URL {
		if let f = fileExtension {
			return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gladys-preview-blob", isDirectory: false).appendingPathExtension(f)
		} else {
			return bytesPath
		}
	}
}
