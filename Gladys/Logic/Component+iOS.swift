import Contacts
import ContactsUI
import GladysCommon
import GladysUI
import GladysUIKit
import MapKit
import QuickLook
import UIKit

final class NavBarHiderNavigationController: UINavigationController {
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        navigationBar.isHidden = true
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

    func animationController(forDismissed _: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        sourceItemView == nil ? nil : self
    }

    func animationController(forPresented _: UIViewController, presenting _: UIViewController, source _: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        sourceItemView == nil ? nil : self
    }

    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.25
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

            if let snapInfo {
                snapInfo.0.frame = snapInfo.1
                vcSnap.frame = snapInfo.1
                container.addSubview(snapInfo.0)
            } else {
                vcSnap.frame = finalFrame.insetBy(dx: 44, dy: 44)
            }

            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: {
                vcSnap.alpha = 1
                vcSnap.frame = finalFrame
                if let snapInfo {
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
            if let snapInfo {
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
                if let snapInfo {
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
        typeItem = item
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
        #if os(iOS)
            guard let currentWindowSize = currentWindow?.bounds.size else { return }
            popoverPresentationController?.presentedViewController.preferredContentSize = CGSize(width: min(768, currentWindowSize.width), height: currentWindowSize.height)
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let ql = QLPreviewController()
        ql.dataSource = self
        ql.delegate = self
        #if os(visionOS)
            view.backgroundColor = .clear
            ql.view.backgroundColor = .clear
            addChildController(ql, to: view)
        #else
            let qlNav = NavBarHiderNavigationController(rootViewController: ql)
            addChildController(qlNav, to: view)
        #endif

        userActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
        userActivity?.needsSave = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateUserActivityState(_ activity: NSUserActivity) {
        super.updateUserActivityState(activity)
        if let relatedItem = typeItem.parent {
            ArchivedItem.updateUserActivity(activity, from: relatedItem, child: typeItem, titled: "Quick look")
        }
    }

    func numberOfPreviewItems(in _: QLPreviewController) -> Int {
        1
    }

    func previewController(_: QLPreviewController, previewItemAt _: Int) -> QLPreviewItem {
        Component.PreviewItem(typeItem: typeItem)
    }

    nonisolated func previewController(_: QLPreviewController, editingModeFor _: QLPreviewItem) -> QLPreviewItemEditingMode {
        .disabled
    }
}

@MainActor
final class ArchivedDropItemActivitySource: NSObject, UIActivityItemSource {
    private let component: Component
    private let previewItem: Component.PreviewItem

    init(component: Component) {
        self.component = component
        previewItem = Component.PreviewItem(typeItem: component)
        super.init()
    }

    nonisolated func activityViewControllerPlaceholderItem(_: UIActivityViewController) -> Any {
        MainActor.assumeIsolated {
            component.encodedUrl ?? previewItem.previewItemURL
        } ?? Data()
    }

    nonisolated func activityViewController(_: UIActivityViewController, itemForActivityType _: UIActivity.ActivityType?) -> Any? {
        MainActor.assumeIsolated {
            component.encodedUrl ?? previewItem.previewItemURL
        }
    }

    nonisolated func activityViewController(_: UIActivityViewController, subjectForActivityType _: UIActivity.ActivityType?) -> String {
        MainActor.assumeIsolated {
            previewItem.previewItemTitle?.truncateWithEllipses(limit: 64) ?? ""
        }
    }

    nonisolated func activityViewController(_: UIActivityViewController, thumbnailImageForActivityType _: UIActivity.ActivityType?, suggestedSize _: CGSize) -> UIImage? {
        MainActor.assumeIsolated {
            component.getComponentIconSync()
        }
    }

    nonisolated func activityViewController(_: UIActivityViewController, dataTypeIdentifierForActivityType _: UIActivity.ActivityType?) -> String {
        MainActor.assumeIsolated {
            component.typeIdentifier
        }
    }

    /*
     func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
         let metadata = LPLinkMetadata()
         metadata.title = component.trimmedSuggestedName

         if let icon = component.componentIcon {
             metadata.imageProvider = NSItemProvider(object: icon)
             metadata.iconProvider = NSItemProvider(object: icon)
         }

         if let url = component.encodedUrl as URL? {
             metadata.originalURL = url
             metadata.url = url
         }

         return metadata
     }
      */
}

extension Component {
    var sharingActivitySource: ArchivedDropItemActivitySource {
        ArchivedDropItemActivitySource(component: self)
    }

    var dragItem: UIDragItem {
        let i = UIDragItem(itemProvider: itemProvider)
        i.localObject = self
        return i
    }

    func quickLook() -> GladysPreviewController? {
        canPreview ? GladysPreviewController(item: self) : nil
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

    @discardableResult
    func tryOpen(in viewController: UINavigationController?) async -> Bool {
        let item = objectForShare
        if let item = item as? MKMapItem {
            item.openInMaps(launchOptions: [:])
            return true

        } else if let contact = item as? CNContact {
            let c = CNContactViewController(forUnknownContact: contact)
            c.contactStore = CNContactStore()
            c.hidesBottomBarWhenPushed = true
            if let viewController {
                viewController.pushViewController(c, animated: true)
            } else {
                let scene = currentWindow?.windowScene
                let request = UIRequest(vc: c, sourceView: nil, sourceRect: nil, sourceButton: nil, pushInsteadOfPresent: true, sourceScene: scene)
                sendNotification(name: .UIRequest, object: request)
            }
            return true

        } else if let item = item as? URL {
            guard let firstScene = UIApplication.shared.connectedScenes.first else {
                return false
            }
            let success = await firstScene.open(item, options: nil)
            if !success {
                let message = if item.isFileURL {
                    "iOS does not recognise the type of this file"
                } else {
                    "iOS does not recognise the type of this link"
                }
                await genericAlert(title: "Can't Open", message: message)
            }
            return success
        } else {
            return false
        }
    }
}
