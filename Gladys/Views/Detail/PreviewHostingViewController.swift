//
//  QLHostingViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 20/10/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit
import QuickLook

final class PreviewHostingInternalController: GladysViewController {
    var qlController: UIViewController?
    
    private var titleObservation: NSKeyValueObservation?
    private var activityObservation: NSKeyValueObservation?
    private var sizeObservation: NSKeyValueObservation?

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = GladysView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        preferredContentSize = mainWindow.bounds.size
        let tint = UIColor(named: "colorTint")
        view.tintColor = tint
        
        windowButtonLocation = .right        
        doneButtonLocation = .right
                
        if let qlController = qlController {
            
            titleObservation = qlController.observe(\.title) { [weak self] q, _ in
                self?.title = q.title
            }
            
            activityObservation = qlController.observe(\.userActivity) { [weak self] q, _ in
                self?.userActivity = q.userActivity
                self?.userActivity?.needsSave = true
            }
            
            sizeObservation = qlController.observe(\.preferredContentSize) { [weak self] q, _ in
                self?.preferredContentSizeDidChange(forChildContentContainer: q)
            }

            addChildController(qlController, to: view)
        }
    }
        
    deinit {
        if let qlController = qlController {
            removeChildController(qlController)
        }
    }
}

final class PreviewHostingViewController: UINavigationController, UIViewControllerAnimatedTransitioning, UIViewControllerTransitioningDelegate {

    weak var sourceItemView: UIView?

    override init(rootViewController: UIViewController) {
        let i = PreviewHostingInternalController(nibName: nil, bundle: nil)
        i.qlController = rootViewController
        super.init(rootViewController: i)
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let tint = UIColor(named: "colorTint")
        view.tintColor = tint
        navigationBar.tintColor = tint
        navigationBar.titleTextAttributes = [
            .font: UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection),
            .foregroundColor: UIColor.secondaryLabel
        ]
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewControllers = []
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
