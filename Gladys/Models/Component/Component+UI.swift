import UIKit
import MapKit
import Contacts
import ContactsUI
import CloudKit
import QuickLook

final class NavBarHiderNavigationController: UINavigationController {    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        self.navigationBar.isHidden = true
    }
}

final class GladysNavController: UINavigationController, UIViewControllerAnimatedTransitioning, UIViewControllerTransitioningDelegate {
    weak var sourceItemView: UIView?

    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        transitioningDelegate = self
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .g_colorPaper
        view.tintColor = .g_colorTint
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return sourceItemView == nil ? nil : self
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return sourceItemView == nil ? nil : self
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.25
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {

        let container = transitionContext.containerView

        var snapInfo: (UIView, CGRect)?
        if let source = sourceItemView, let snapImage = source.snapshotView(afterScreenUpdates: false) {
            let snapFrame = container.convert(source.bounds, from: source)
            snapInfo = (snapImage, snapFrame)
        }

        if isBeingPresented {
            guard let vc = transitionContext.viewController(forKey: .to) else { return }
            let finalFrame = transitionContext.finalFrame(for: vc)
            vc.view.frame = finalFrame
            vc.view.layoutIfNeeded()

            let vcSnap = vc.view.snapshotView(afterScreenUpdates: true)!
            vcSnap.alpha = 0
            container.addSubview(vcSnap)

            if let snapInfo = snapInfo {
                snapInfo.0.frame = snapInfo.1
                vcSnap.frame = snapInfo.1
                container.addSubview(snapInfo.0)
            } else {
                vcSnap.frame = finalFrame.insetBy(dx: 44, dy: 44)
            }

            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: {
                vcSnap.alpha = 1
                vcSnap.frame = finalFrame
                if let snapInfo = snapInfo {
                    snapInfo.0.frame = finalFrame
                    snapInfo.0.alpha = 0
                }
            }, completion: { _ in
                vcSnap.removeFromSuperview()
                container.addSubview(vc.view)
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            })

        } else {
            guard let vc = transitionContext.viewController(forKey: .from) else { return }
            let vcSnap = vc.view.snapshotView(afterScreenUpdates: true)!
            vcSnap.frame = vc.view.frame
            vc.view.isHidden = true
            container.addSubview(vcSnap)

            let finalFrame: CGRect
            if let snapInfo = snapInfo {
                finalFrame = snapInfo.1
                snapInfo.0.frame = vcSnap.frame
                snapInfo.0.alpha = 0
                container.addSubview(snapInfo.0)
            } else {
                finalFrame = vcSnap.frame.insetBy(dx: 44, dy: 44)
            }

            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: {
                vcSnap.frame = finalFrame
                vcSnap.alpha = 0
                if let snapInfo = snapInfo {
                    snapInfo.0.frame = finalFrame
                    snapInfo.0.alpha = 1
                }
            }, completion: { _ in
                vcSnap.removeFromSuperview()
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            })
        }
    }
}

final class GladysPreviewController: GladysViewController, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    private var typeItem: Component
    
    init(item: Component) {
        self.typeItem = item
        super.init(nibName: nil, bundle: nil)
        title = item.oneTitle
        doneButtonLocation = .right
        windowButtonLocation = .right
    }
    
    override func loadView() {
        view = GladysView()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let currentWindowSize = currentWindow?.bounds.size else { return }
        popoverPresentationController?.presentedViewController.preferredContentSize = CGSize(width: min(768, currentWindowSize.width), height: currentWindowSize.height)
    }
    
    private lazy var qlNav: UINavigationController = {
        let ql = QLPreviewController()
        ql.dataSource = self
        ql.delegate = self
        return NavBarHiderNavigationController(rootViewController: ql)
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        addChildController(qlNav, to: view)
        
        userActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
        userActivity?.needsSave = true
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
        
    func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
        return .disabled
    }
}

extension Component {

	var dragItem: UIDragItem {
		let i = UIDragItem(itemProvider: itemProvider)
		i.localObject = self
		return i
	}

    func quickLook() -> GladysPreviewController? {
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
    
    var canOpen: Bool {
        let item = objectForShare
        if item is MKMapItem {
            return true
        } else if item is CNContact {
            return true
        } else if let url = item as? URL {
            return !url.isFileURL && UIApplication.shared.canOpenURL(url)
        }

        return false
    }
    
    func tryOpen(in viewController: UINavigationController?) {
        let item = objectForShare
        if let item = item as? MKMapItem {
            item.openInMaps(launchOptions: [:])

        } else if let contact = item as? CNContact {
            let c = CNContactViewController(forUnknownContact: contact)
            c.contactStore = CNContactStore()
            c.hidesBottomBarWhenPushed = true
            if let viewController = viewController {
                viewController.pushViewController(c, animated: true)
            } else {
                let scene = currentWindow?.windowScene
                let request = UIRequest(vc: c, sourceView: nil, sourceRect: nil, sourceButton: nil, pushInsteadOfPresent: true, sourceScene: scene)
                NotificationCenter.default.post(name: .UIRequest, object: request)
            }

        } else if let item = item as? URL {
            UIApplication.shared.connectedScenes.first?.open(item, options: nil) { success in
                if !success {
                    let message: String
                    if item.isFileURL {
                        message = "iOS does not recognise the type of this file"
                    } else {
                        message = "iOS does not recognise the type of this link"
                    }
                    genericAlert(title: "Can't Open", message: message)
                }
            }
        }
    }
}
