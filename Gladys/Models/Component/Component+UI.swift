import UIKit
import MapKit
import Contacts
import CloudKit
import QuickLook

/*
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
*/

final class GladysPreviewController: QLPreviewController, QLPreviewControllerDataSource {
    private var typeItem: Component
        
    init(item: Component) {
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
            ArchivedItem.updateUserActivity(activity, from: relatedItem, child: typeItem, titled: "Quick look")
        }
    }
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return Component.PreviewItem(typeItem: typeItem)
    }
}

extension Component {

	var dragItem: UIDragItem {
		let i = UIDragItem(itemProvider: itemProvider)
		i.localObject = self
		return i
	}

    func quickLook() -> UIViewController? {
        return canPreview ? GladysPreviewController(item: self) : nil
	}
    
	var canPreview: Bool {
		if let canPreviewCache = canPreviewCache {
			return canPreviewCache
		}
        let res: Bool
        #if targetEnvironment(macCatalyst)
            res = isWebArchive || QLPreviewController.canPreviewItem(PreviewItem(typeItem: self))
        #else
            res = isWebArchive || QLPreviewController.canPreview(PreviewItem(typeItem: self))
        #endif
		canPreviewCache = res
		return res
	}
}
