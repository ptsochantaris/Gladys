
import UIKit
import MapKit
import Contacts
import CloudKit
import QuickLook
import LinkPresentation

final class LinkViewController: UIViewController {
    var url: URL!
    
    @IBOutlet private weak var statusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        LPMetadataProvider().startFetchingMetadata(for: url) { data, error in
            DispatchQueue.main.async {
                self.statusLabel.text = error?.localizedDescription
                if let data = data {
                    self.statusLabel.text = nil
                    let linkPreview = LPLinkView(metadata: data)
                    linkPreview.frame = self.view.bounds
                    self.view.addSubview(linkPreview)
                }
            }
        }
    }
}

extension ArchivedDropItemType: QLPreviewControllerDataSource {

	var dragItem: UIDragItem {
		let i = UIDragItem(itemProvider: itemProvider)
		i.localObject = self
		return i
	}

    func quickLook(extraRightButton: UIBarButtonItem?) -> UIViewController? {
        var ret: UIViewController?
        
		if isWebURL, let url = encodedUrl {
            let d = ViewController.shared.storyboard!.instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
            d.title = "Loading..."
            d.address = url as URL
            d.relatedItem = Model.item(uuid: parentUuid)
            d.relatedChildItem = self
			ret = d

		} else if isWebArchive {
			let d = ViewController.shared.storyboard!.instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading..."
			d.webArchive = PreviewItem(typeItem: self)
			d.relatedItem = Model.item(uuid: parentUuid)
			d.relatedChildItem = self
            ret = d

		} else if canPreview {
			let d = QLPreviewController()
			d.title = oneTitle
			d.dataSource = self
			d.modalPresentationStyle = .popover
			d.preferredContentSize = mainWindow.bounds.size
            ret = d
		}
        
        if let n = ret?.navigationItem, let extra = extraRightButton {
            var buttons = n.rightBarButtonItems ?? [UIBarButtonItem]()
            buttons.append(extra)
            n.rightBarButtonItems = buttons
        }

		return ret
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
		let res = isWebArchive || qlPreview
		canPreviewCache = res
		return res
	}
    
    private var qlPreview: Bool {
        return QLPreviewController.canPreview(PreviewCheckItem(typeItem: self))
    }
}
