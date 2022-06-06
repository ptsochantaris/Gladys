//
//  SelfSizingViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 24/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class SelfSizingTabController: UITabBarController, UITabBarControllerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()

        let i = PersistedOptions.lastSelectedPreferencesTab
        if i < (viewControllers?.count ?? 0) {
            selectedIndex = i
        }
        delegate = self

        let n = NotificationCenter.default
        n.post(name: .PreferencesOpen, object: nil)
        n.addObserver(self, selector: #selector(otherPrefsOpened), name: .PreferencesOpen, object: nil)
    }

    @objc private func otherPrefsOpened() {
        dismiss(animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sizeWindow()
    }

    func tabBarController(_: UITabBarController, didSelect viewController: UIViewController) {
        sizeWindow()
        if let index = viewControllers?.firstIndex(of: viewController) {
            PersistedOptions.lastSelectedPreferencesTab = index
        }
    }

    func sizeWindow() {
        if let n = selectedViewController as? UINavigationController, let v = n.topViewController {
            n.view.layoutIfNeeded()
            var size = CGSize(width: 320, height: tabBar.frame.height + n.navigationBar.frame.height)
            if let s = v.view.subviews.first as? UIScrollView {
                size.height += s.contentSize.height
            }
            preferredContentSize = size
        }
    }
}
