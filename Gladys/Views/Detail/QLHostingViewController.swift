//
//  QLHostingViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 20/10/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class QLHostingViewController: UINavigationController, UIViewControllerAnimatedTransitioning, UIViewControllerTransitioningDelegate {

    var relatedItem: ArchivedDropItem?
    var relatedChildItem: ArchivedDropItemType?
    weak var sourceItemView: UIView?

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = mainWindow.bounds.size
        let tint = ViewController.tintColor
        view.tintColor = tint
        navigationBar.tintColor = tint
        if let sourceBar = ViewController.shared.navigationController?.navigationBar {
            navigationBar.titleTextAttributes = sourceBar.titleTextAttributes
            navigationBar.barTintColor = sourceBar.barTintColor
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if relatedItem != nil {
            userActivity = NSUserActivity(activityType: kGladysQuicklookActivity)
        }
    }
    override func updateUserActivityState(_ activity: NSUserActivity) {
        super.updateUserActivityState(activity)
        if let relatedItem = relatedItem {
            ArchivedDropItem.updateUserActivity(activity, from: relatedItem, child: relatedChildItem, titled: "Quick look")
        }
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
            }) { _ in
                vcSnap.removeFromSuperview()
                container.addSubview(vc.view)
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }

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
            }) { _ in
                vcSnap.removeFromSuperview()
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }
        }
    }
}
