import StoreKit
import UIKit
import GladysCommon

final class AboutController: GladysViewController {
    @IBOutlet private var versionLabel: UIBarButtonItem!
    @IBOutlet private var logo: UIImageView!
    @IBOutlet private var logoSize: NSLayoutConstraint!

    @IBOutlet private var supportStack: UIStackView!
    @IBOutlet private var testFlightStack: UIStackView!
    @IBOutlet private var topStack: UIStackView!

    @IBOutlet private var p1: UIView!
    @IBOutlet private var p2: UIView!
    @IBOutlet private var p3: UIView!
    @IBOutlet private var p4: UIView!
    @IBOutlet private var p5: UIView!

    @IBOutlet private var b1: UIButton!
    @IBOutlet private var b2: UIButton!
    @IBOutlet private var b3: UIButton!
    @IBOutlet private var b4: UIButton!
    @IBOutlet private var b5: UIButton!

    @IBOutlet private var t1: UILabel!
    @IBOutlet private var t2: UILabel!
    @IBOutlet private var t3: UILabel!
    @IBOutlet private var t4: UILabel!
    @IBOutlet private var t5: UILabel!

    @IBOutlet private var l1: UILabel!
    @IBOutlet private var l2: UILabel!
    @IBOutlet private var l3: UILabel!
    @IBOutlet private var l4: UILabel!
    @IBOutlet private var l5: UILabel!

    private var tipJar: TipJar?
    private var tipItems: [SKProduct]?

    override func viewDidLoad() {
        super.viewDidLoad()

        supportStack.isHidden = true

        if isRunningInTestFlightEnvironment {
            testFlightStack.isHidden = false
        } else {
            testFlightStack.isHidden = true

            tipJar = TipJar { [weak self] items, _ in
                guard let s = self, let items, items.count > 4 else { return }

                s.tipItems = items
                s.l1.text = items[0].regularPrice
                s.l2.text = items[1].regularPrice
                s.l3.text = items[2].regularPrice
                s.l4.text = items[3].regularPrice
                s.l5.text = items[4].regularPrice

                s.b1.accessibilityValue = s.l1.text
                s.b2.accessibilityValue = s.l2.text
                s.b3.accessibilityValue = s.l3.text
                s.b4.accessibilityValue = s.l4.text
                s.b5.accessibilityValue = s.l5.text

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

    @IBAction private func aboutSelected(_: UIButton) {
        guard let u = URL(string: "https://bru.build/app/gladys") else { return }
        UIApplication.shared.connectedScenes.first?.open(u, options: nil) { success in
            if success {
                self.done()
            }
        }
    }

    @IBAction private func testingSelected(_: UIButton) {
        UIApplication.shared.open(URL(string: "http://www.bru.build/gladys-beta-for-ios")!, options: [:], completionHandler: nil)
    }

    private func purchase(index: Int) {
        guard let tipJar, let items = tipItems else { return }

        let t = [t1!, t2!, t3!, t4!, t5!]
        let prev = t[index].text
        t[index].text = "✅"
        view.isUserInteractionEnabled = false
        tipJar.requestItem(items[index]) {
            t[index].text = prev
            self.view.isUserInteractionEnabled = true
        }
    }

    @IBAction private func p1Selected(_: UIButton) {
        purchase(index: 0)
    }

    @IBAction private func p2Selected(_: UIButton) {
        purchase(index: 1)
    }

    @IBAction private func p3Selected(_: UIButton) {
        purchase(index: 2)
    }

    @IBAction private func p4Selected(_: UIButton) {
        purchase(index: 3)
    }

    @IBAction private func p5Selected(_: UIButton) {
        purchase(index: 4)
    }
}
