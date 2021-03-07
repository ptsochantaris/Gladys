//
//  CreditsViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 25/04/2020.
//  Copyright © 2020 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class CreditsViewController: GladysViewController {
    
    @IBOutlet private var scrollView: UIScrollView!
    
    @IBAction private func authorSelected(_ sender: UIButton) {
        UIApplication.shared.open(URL(string: "http://bru.build")!)
    }

    @IBAction private func fuziSelected(_ sender: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/cezheng/Fuzi")!)
    }

    @IBAction private func zipSelected(_ sender: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/weichsel/ZIPFoundation")!)
    }

    @IBAction private func callbackSelected(_ sender: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/phimage/CallbackURLKit")!)
    }

    @IBAction private func diffSelected(_ sender: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/onmyway133/DeepDiff")!)
    }

    @IBAction private func lintSelected(_ sender: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/realm/SwiftLint")!)
    }
        
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let tabs = tabBarController as? SelfSizingTabController else {
            return
        }
        preferredContentSize = scrollView.contentSize
        tabs.sizeWindow()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard let tabs = tabBarController as? SelfSizingTabController else {
            return
        }
        tabs.sizeWindow()
    }
}
