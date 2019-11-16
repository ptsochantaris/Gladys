
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
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIAccessibility.post(notification: UIAccessibility.Notification.screenChanged, argument: view)
    }
    
}

final class GladysPreviewController: QLPreviewController, QLPreviewControllerDataSource {
    private var typeItem: ArchivedDropItemType
        
    init(item: ArchivedDropItemType) {
        self.typeItem = item
        super.init(nibName: nil, bundle: nil)
        title = item.oneTitle
        dataSource = self
        modalPresentationStyle = .popover
        preferredContentSize = mainWindow.bounds.size
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()                
        userActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    override func updateUserActivityState(_ activity: NSUserActivity) {
        super.updateUserActivityState(activity)
        if let relatedItem = typeItem.parent {
            ArchivedDropItem.updateUserActivity(activity, from: relatedItem, child: typeItem, titled: "Quick look")
        }
    }
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return ArchivedDropItemType.PreviewItem(typeItem: typeItem)
    }
}

extension ArchivedDropItemType {

	var dragItem: UIDragItem {
		let i = UIDragItem(itemProvider: itemProvider)
		i.localObject = self
		return i
	}

    func quickLook(in scene: UIWindowScene?) -> UIViewController? {
        
		if isWebURL, let url = encodedUrl {
            let d = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
            d.title = "Loading..."
            d.address = url as URL
            d.relatedItem = Model.item(uuid: parentUuid)
            d.relatedChildItem = self
            return d

		} else if isWebArchive {
			let d = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "WebPreview") as! WebPreviewController
			d.title = "Loading..."
			d.webArchive = PreviewItem(typeItem: self)
			d.relatedItem = Model.item(uuid: parentUuid)
			d.relatedChildItem = self
            return d

		} else if canPreview {
            return GladysPreviewController(item: self)
		}
        
		return nil
	}
    
	var canPreview: Bool {
		if let canPreviewCache = canPreviewCache {
			return canPreviewCache
		}
		let res = isWebArchive || QLPreviewController.canPreview(PreviewCheckItem(typeItem: self))
		canPreviewCache = res
		return res
	}
}
