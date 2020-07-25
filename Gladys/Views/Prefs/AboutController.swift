//
//  AboutController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 05/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import StoreKit
import GladysFramework

final class AboutController: GladysViewController {

    @IBOutlet private weak var versionLabel: UIBarButtonItem!
	@IBOutlet private weak var logo: UIImageView!
    @IBOutlet private weak var logoSize: NSLayoutConstraint!
    
    @IBOutlet private weak var supportStack: UIStackView!
    @IBOutlet private weak var testFlightStack: UIStackView!
    @IBOutlet private weak var topStack: UIStackView!
    
    @IBOutlet private weak var p1: UIView!
    @IBOutlet private weak var p2: UIView!
    @IBOutlet private weak var p3: UIView!
    @IBOutlet private weak var p4: UIView!
    @IBOutlet private weak var p5: UIView!

    @IBOutlet private weak var t1: UILabel!
    @IBOutlet private weak var t2: UILabel!
    @IBOutlet private weak var t3: UILabel!
    @IBOutlet private weak var t4: UILabel!
    @IBOutlet private weak var t5: UILabel!
    
    @IBOutlet private weak var l1: UILabel!
    @IBOutlet private weak var l2: UILabel!
    @IBOutlet private weak var l3: UILabel!
    @IBOutlet private weak var l4: UILabel!
    @IBOutlet private weak var l5: UILabel!

    private var tipJar: TipJar?
    private var tipItems: [SKProduct]?
    
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag, completion: completion)
    }
    
	override func viewDidLoad() {
		super.viewDidLoad()
                
        supportStack.isHidden = true

        if isRunningInTestFlightEnvironment() {
            testFlightStack.isHidden = false
        } else {
            testFlightStack.isHidden = true
            
            tipJar = TipJar { [weak self] items, _ in
                guard let s = self, let items = items, items.count > 4 else { return }

                s.tipItems = items
                s.l1.text = items[0].regularPrice
                s.l2.text = items[1].regularPrice
                s.l3.text = items[2].regularPrice
                s.l4.text = items[3].regularPrice
                s.l5.text = items[4].regularPrice

                if s.firstAppearance {
                    s.supportStack.isHidden = false
                } else {
                    UIView.animate(withDuration: 0.2) {
                        s.supportStack.isHidden = false
                    }
                }
                (s.tabBarController as? SelfSizingTabController)?.sizeWindow()
            }
            
            for v in [p1, p2, p3, p4, p5] {
                v?.layer.cornerRadius = 8
            }
        }
        
        doneButtonLocation = .right

        if let i = Bundle.main.infoDictionary,
            let v = i["CFBundleShortVersionString"] as? String,
            let b = i["CFBundleVersion"] as? String {
            
            versionLabel.title = "v\(v) (\(b))"
        }
    }
    
    override func updateViewConstraints() {
        if view.bounds.height > 600 {
            logoSize.constant = 160
            topStack.spacing = 32
        }
        super.updateViewConstraints()
    }
                    
    override func viewDidAppear(_ animated: Bool) {
        if !firstAppearance {
            (tabBarController as? SelfSizingTabController)?.sizeWindow()
        }
        super.viewDidAppear(animated)
    }

	@IBAction private func aboutSelected(_ sender: UIButton) {
        guard let u = URL(string: "https://bru.build/app/gladys") else { return }
        UIApplication.shared.connectedScenes.first?.open(u, options: nil) { success in
			if success {
				self.done()
			}
		}
	}
    
    @IBAction private func testingSelected(_ sender: UIButton) {
        UIApplication.shared.open(URL(string: "http://www.bru.build/gladys-beta-for-ios")!, options: [:], completionHandler: nil)
    }
    
    private func purchase(index: Int) {
        guard let tipJar = tipJar, let items = self.tipItems else { return }
        
        let t = [t1!, t2!, t3!, t4!, t5!]
        let prev = t[index].text
        t[index].text = "✅"
        view.isUserInteractionEnabled = false
        tipJar.requestItem(items[index]) {
            t[index].text = prev
            self.view.isUserInteractionEnabled = true
        }
    }
    
    @IBAction private func p1Selected(_ sender: UIButton) {
        purchase(index: 0)
    }

    @IBAction private func p2Selected(_ sender: UIButton) {
        purchase(index: 1)
    }

    @IBAction private func p3Selected(_ sender: UIButton) {
        purchase(index: 2)
    }

    @IBAction private func p4Selected(_ sender: UIButton) {
        purchase(index: 3)
    }
    
    @IBAction private func p5Selected(_ sender: UIButton) {
        purchase(index: 4)
    }

}
