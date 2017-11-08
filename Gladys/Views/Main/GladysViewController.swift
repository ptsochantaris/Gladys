//
//  GladysViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 19/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

class GladysViewController: UIViewController {

	enum DoneLocation {
		case none, left, right
	}
	var doneLocation = DoneLocation.none

	var initialAccessibilityElement: UIView {
		return navigationController?.navigationBar ?? view
	}

	func focusInitialAccessibilityElement() {
		UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, initialAccessibilityElement)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if popoverPresenter != nil {
			UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, initialAccessibilityElement)
		}
	}

	private var popoverPresenter: UIViewController? {
		return popoverPresentationController?.presentingViewController ?? navigationController?.popoverPresentationController?.presentingViewController
	}

	private weak var vcToFocusAfterDismissal: UIViewController?

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if navigationController?.isBeingDismissed ?? isBeingDismissed, let v = popoverPresenter {
			if let v = v as? UINavigationController {
				vcToFocusAfterDismissal = v.viewControllers.last
			} else {
				vcToFocusAfterDismissal = v
			}
		}
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		if let v = vcToFocusAfterDismissal {
			if let v = v as? GladysViewController {
				UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, v.initialAccessibilityElement)
			} else {
				UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, v.view)
			}
		}
	}

	@objc func done() {
		if let n = navigationController, let p = n.popoverPresentationController, let d = p.delegate, let f = d.popoverPresentationControllerShouldDismissPopover {
			_ = f(p)
		}
		dismiss(animated: true)
	}

	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()
		let s = popoverPresentationController?.adaptivePresentationStyle.rawValue ?? 0
		showDone(s == 0 && ViewController.shared.traitCollection.horizontalSizeClass == .compact || UIAccessibilityIsVoiceOverRunning())
	}

	private func showDone(_ show: Bool) {
		switch doneLocation {
		case .left:
			if show && navigationItem.leftBarButtonItem == nil {
				navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
			} else if !show && navigationItem.leftBarButtonItem != nil {
				navigationItem.leftBarButtonItem = nil
			}
		case .right:
			if show && navigationItem.rightBarButtonItem == nil {
				navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
			} else if !show && navigationItem.rightBarButtonItem != nil {
				navigationItem.rightBarButtonItem = nil
			}
		case .none:
			break
		}
	}
}
