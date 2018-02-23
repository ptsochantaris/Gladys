//
//  SelfSizingViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 24/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

class SelfSizingTabController: UITabBarController, UITabBarControllerDelegate {

	override func viewDidLoad() {
		super.viewDidLoad()

		let i = PersistedOptions.lastSelectedPreferencesTab
		if i < (viewControllers?.count ?? 0) {
			selectedIndex = i
		}
		delegate = self
		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(darkModeChanged), name: .DarkModeChanged, object: nil)
		darkModeChanged()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@objc private func darkModeChanged() {
		let bar = tabBar
		bar.barTintColor = GladysViewController.darkColor
		bar.tintColor = GladysViewController.tintColor
	}

	private var firstView = true
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if firstView {
			firstView = false
			sizeWindow(animate: false)
		}
	}

	func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
		sizeWindow(animate: true)
		if let index = viewControllers?.index(of: viewController) {
			PersistedOptions.lastSelectedPreferencesTab = index
		}
	}
	
	private func sizeWindow(animate: Bool) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			if let n = self.selectedViewController as? UINavigationController, let v = n.topViewController {
				var size = v.view.systemLayoutSizeFitting(CGSize(width: 320, height: 0),
														  withHorizontalFittingPriority: .required,
														  verticalFittingPriority: .fittingSizeLevel)
				if let s = v.view.subviews.first as? UIScrollView {
					size.height += s.contentSize.height
				}
				if animate {
					self.preferredContentSize = size
				} else {
					UIView.performWithoutAnimation {
						self.preferredContentSize = size
					}
				}
			}
		}
	}
}
