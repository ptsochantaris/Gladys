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

	override func viewDidLoad() {
		super.viewDidLoad()
		darkModeChanged()
		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(darkModeChanged), name: .DarkModeChanged, object: nil)
	}

	@objc func darkModeChanged() {
		guard let nav = navigationController?.navigationBar, let bar = navigationController?.toolbar else { return }

		let d = GladysViewController.darkColor
		nav.barTintColor = d
		bar.barTintColor = d

		let c = GladysViewController.tintColor
		nav.tintColor = c
		view.tintColor = c
		bar.tintColor = c
	}

	static var tintColor: UIColor {
		if PersistedOptions.darkMode {
			return .lightGray
		} else {
			return #colorLiteral(red: 0.5764705882, green: 0.09411764706, blue: 0.07058823529, alpha: 1)
		}
	}

	static var darkColor: UIColor? {
		if PersistedOptions.darkMode {
			return #colorLiteral(red: 0.1960784314, green: 0.1960784314, blue: 0.1960784314, alpha: 1)
		}
		return nil
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
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

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		checkDoneLocation()
	}

	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()
		checkDoneLocation()
	}

	private func checkDoneLocation() {
		if doneLocation != .none {
			if UIAccessibilityIsVoiceOverRunning() {
				showDone(true)
				return
			}

			let s = popoverPresentationController?.adaptivePresentationStyle.rawValue ?? 0
			if s == -1 { // hovering
				if ViewController.shared.traitCollection.horizontalSizeClass == .compact {
					showDone(false)
				} else {
					showDone(ViewController.shared.traitCollection.verticalSizeClass == .compact)
				}
			} else { // full window?
				showDone(ViewController.shared.phoneMode)
			}
		}
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
