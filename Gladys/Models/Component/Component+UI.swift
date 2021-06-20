import UIKit
import MapKit
import Contacts
import ContactsUI
import CloudKit
import QuickLook

final class GladysNavController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .g_colorPaper
        view.tintColor = .g_colorTint
    }
}

final class GladysPreviewController: QLPreviewController, QLPreviewControllerDataSource, UIViewControllerAnimatedTransitioning, UIViewControllerTransitioningDelegate {
    private var typeItem: Component
    
    weak var sourceItemView: UIView?
    
    init(item: Component) {
        self.typeItem = item
        super.init(nibName: nil, bundle: nil)
        title = item.oneTitle
        dataSource = self
        modalPresentationStyle = .overFullScreen
        transitioningDelegate = self

        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(multipleWindowModeChange), name: .MultipleWindowModeChange, object: nil)
    }
    
    @objc private func multipleWindowModeChange() {
        navigationController?.navigationBar.setNeedsLayout()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let currentWindowSize = currentWindow?.bounds.size else { return }
        popoverPresentationController?.presentedViewController.preferredContentSize = CGSize(width: min(768, currentWindowSize.width), height: currentWindowSize.height)
    }
    
    private lazy var doneButton: UIBarButtonItem = {
        return makeDoneButton(target: self, action: #selector(done))
    }()
    
    private lazy var mainWindowButton: UIBarButtonItem = {
        let b = UIBarButtonItem(title: "Main Window", style: .plain, target: self, action: #selector(mainWindowSelected))
        b.image = UIImage(systemName: "square.grid.2x2")
        return b
    }()
    
    private lazy var newWindowButton: UIBarButtonItem = {
        let b = UIBarButtonItem(title: "New Window", style: .plain, target: self, action: #selector(newWindowSelected))
        b.image = UIImage(systemName: "uiwindow.split.2x1")
        return b
    }()

    @objc private func newWindowSelected() {
        let activity = userActivity
        done()
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = view.window?.windowScene
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: options) { error in
            log("Error opening new window: \(error.localizedDescription)")
        }
    }

    @objc private func mainWindowSelected() {
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = view.window?.windowScene
        let mainWindowSession = UIApplication.shared.openSessions.first { $0.isMainWindow }
        UIApplication.shared.requestSceneSessionActivation(mainWindowSession, userActivity: nil, options: options) { error in
            log("Error opening new window: \(error.localizedDescription)")
        }
    }

    // cloning updateButtons from GladysViewController
    override var navigationItem: UINavigationItem {
        let i = super.navigationItem
        i.title = self.title
                
        var showDone = false
        var showMainWindow = false
        var showNewWindow = false
        
        if phoneMode {
            showDone = true
            
        } else if Singleton.shared.openCount > 1 {
            if UIAccessibility.isVoiceOverRunning {
                showDone = true
                
            } else if isHovering { // hovering
                if self.traitCollection.verticalSizeClass == .compact {
                    showDone = true
                }
                
            } else if popoverPresentationController == nil { // full window?
                showDone = true
            }
            
        } else if navigationController?.viewControllers.count == 1 && popoverPresentationController == nil { // fullscreen
            showDone = true
        }
        
        if UIApplication.shared.supportsMultipleScenes {
            if isAccessoryWindow {
                if Singleton.shared.openCount <= 1 {
                    showMainWindow = true
                }
            } else {
                showNewWindow = true
            }
        }
        
        var rightItems = [UIBarButtonItem]()

        let mainWindowIndex = rightItems.firstIndex(of: mainWindowButton)
        if showMainWindow && mainWindowIndex == nil {
            rightItems.insert(mainWindowButton, at: 0)
        } else if !showMainWindow, let mainWindowIndex = mainWindowIndex {
            rightItems.remove(at: mainWindowIndex)
        }

        let doneIndex = rightItems.firstIndex(of: doneButton)
        if showDone && doneIndex == nil {
            rightItems.insert(doneButton, at: 0)
        } else if !showDone, let doneIndex = doneIndex {
            rightItems.remove(at: doneIndex)
        }
        
        i.rightBarButtonItems = rightItems

        if showDone {
            doneButton.target = self
            doneButton.action = #selector(done)
            doneButton.isEnabled = true
        }
        
        if showNewWindow {
            newWindowButton.target = self
            newWindowButton.action = #selector(newWindowSelected)
            newWindowButton.isEnabled = true
        }
        
        if showMainWindow {
            mainWindowButton.target = self
            mainWindowButton.action = #selector(mainWindowSelected)
            mainWindowButton.isEnabled = true
        }
        
        return i
    }
    
    @objc private func done() {
        NotificationCenter.default.removeObserver(self) // avoid any notifications while being dismissed or if we stick around for a short while
        if isAccessoryWindow, let session = (navigationController?.viewIfLoaded ?? viewIfLoaded)?.window?.windowScene?.session {
            let options = UIWindowSceneDestructionRequestOptions()
            options.windowDismissalAnimation = .standard
            UIApplication.shared.requestSceneSessionDestruction(session, options: options, errorHandler: nil)
        } else {
            dismiss(animated: true)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        edgesForExtendedLayout = []
        userActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
        userActivity?.needsSave = true
        
        let tint = UIColor.g_colorTint
        view.tintColor = tint

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [
            .font: UIFont.preferredFont(forTextStyle: .callout),
            .foregroundColor: UIColor.g_colorComponentLabel
        ]

        if let nav = navigationController, nav.viewControllers.first == self {
            nav.navigationBar.tintColor = tint
            if isAccessoryWindow {
                appearance.backgroundColor = nav.view.backgroundColor
            }
        }
        
        navigationItem.standardAppearance = appearance
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
    
    // animated transitioning

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return self
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return self
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
