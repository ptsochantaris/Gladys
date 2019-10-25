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
		UIAccessibility.post(notification: .layoutChanged, argument: initialAccessibilityElement)
	}

	static var tintColor: UIColor {
        return #colorLiteral(red: 0.5764705882, green: 0.09411764706, blue: 0.07058823529, alpha: 1)
	}

	static var darkColor: UIColor? {
		return nil
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if popoverPresenter != nil {
			UIAccessibility.post(notification: .layoutChanged, argument: initialAccessibilityElement)
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
				UIAccessibility.post(notification: .layoutChanged, argument: v.initialAccessibilityElement)
			} else {
				UIAccessibility.post(notification: .layoutChanged, argument: v.view)
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
			if UIAccessibility.isVoiceOverRunning {
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

	private var scrollTimer: GladysTimer?
	private var scrollLink: CADisplayLink?
	private var scrollView: UIScrollView?

	override var keyCommands: [UIKeyCommand]? {
		var a = [
			UIKeyCommand(title: "Scroll Down", action: #selector(scrollDown), input: UIKeyCommand.inputUpArrow),
			UIKeyCommand(title: "Scroll Up", action: #selector(scrollUp), input: UIKeyCommand.inputDownArrow),
		]
		if self.popoverPresenter != nil {
			let w = UIKeyCommand(input: "w", modifierFlags: .command, action: #selector(done), discoverabilityTitle: "Close This View")
			a.insert(w, at: 0)
		}
		return a
	}

	@objc private func scrollUp() {
		startScroll(#selector(scrollLineUp))
	}

	@objc private func scrollDown() {
		startScroll(#selector(scrollLineDown))
	}

	private func startScroll(_ selector: Selector) {
		scrollLink?.invalidate()
		guard let scr = view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView else { return }
		scrollView = scr
		scrollLink = CADisplayLink(target: self, selector: selector)
		scrollLink!.add(to: RunLoop.main, forMode: .common)
		scrollTimer = GladysTimer(interval: 0.4) {
			self.scrollLink?.invalidate()
			self.scrollLink = nil
			self.scrollView = nil
		}
	}

	@objc private func scrollLineUp() {
		if let firstScrollView = scrollView {
			var newPos = firstScrollView.contentOffset
			let maxY = (firstScrollView.contentSize.height - firstScrollView.bounds.size.height) + firstScrollView.adjustedContentInset.bottom
			newPos.y = min(firstScrollView.contentOffset.y+8, maxY)
			firstScrollView.setContentOffset(newPos, animated: false)
		}
	}

	@objc private func scrollLineDown() {
		if let firstScrollView = scrollView {
			var newPos = firstScrollView.contentOffset
			newPos.y = max(newPos.y-8, -firstScrollView.adjustedContentInset.top)
			firstScrollView.setContentOffset(newPos, animated: false)
		}
	}

	private func showDone(_ show: Bool) {
		switch doneLocation {
		case .left:
			var leftItems = navigationItem.leftBarButtonItems ?? []
			if show && !leftItems.contains(doneButton) {
				leftItems.insert(doneButton, at: 0)
				navigationItem.leftBarButtonItems = leftItems
			} else if !show && leftItems.contains(doneButton) {
				navigationItem.leftBarButtonItems = leftItems.filter { $0 != doneButton }
			}
		case .right:
			var rightItems = navigationItem.rightBarButtonItems ?? []
			if show && !rightItems.contains(doneButton) {
				rightItems.insert(doneButton, at: 0)
				navigationItem.rightBarButtonItems = rightItems
			} else if !show && rightItems.contains(doneButton) {
				navigationItem.rightBarButtonItems = rightItems.filter { $0 != doneButton }
			}
		case .none:
			break
		}
	}

	private lazy var doneButton: UIBarButtonItem = {
		return UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
	}()
}
