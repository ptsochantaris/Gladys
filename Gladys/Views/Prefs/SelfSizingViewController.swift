//
//  SelfSizingViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 24/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

class SelfSizingTabController: UITabBarController, UITabBarControllerDelegate {

	private var firstView = true
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		delegate = self
		if firstView {
			firstView = false
			sizeWindow()
		}
	}

	func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
		sizeWindow()
	}
	
	private func sizeWindow() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			if let n = self.selectedViewController as? UINavigationController, let v = n.topViewController {
				var size = v.view.systemLayoutSizeFitting(CGSize(width: 320, height: 0),
														  withHorizontalFittingPriority: .required,
														  verticalFittingPriority: .fittingSizeLevel)
				if let s = v.view.subviews.first as? UIScrollView {
					size.height += s.contentSize.height
				}
				self.preferredContentSize = size
			}
		}
	}
}
