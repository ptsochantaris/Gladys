import GladysCommon
import GladysUI
import GladysUIKit
import StoreKit
import UIKit

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

    override func viewDidLoad() {
        super.viewDidLoad()

        supportStack.isHidden = true

        if isRunningInTestFlightEnvironment {
            testFlightStack.isHidden = false
        } else {
            testFlightStack.isHidden = true

            Task { @MainActor in
                await TipJar.shared.setupIfNeeded()

                let fetchedProducts = TipJar.shared.tips.compactMap(\.fetchedProduct)
                guard fetchedProducts.isPopulated else { return }

                l1.text = fetchedProducts[0].displayPrice
                l2.text = fetchedProducts[1].displayPrice
                l3.text = fetchedProducts[2].displayPrice
                l4.text = fetchedProducts[3].displayPrice
                l5.text = fetchedProducts[4].displayPrice

                b1.accessibilityValue = l1.text
                b2.accessibilityValue = l2.text
                b3.accessibilityValue = l3.text
                b4.accessibilityValue = l4.text
                b5.accessibilityValue = l5.text

                if firstAppearance {
                    supportStack.isHidden = false
                } else {
                    UIView.animate(withDuration: 0.2) { [weak self] in
                        self?.supportStack.isHidden = false
                    }
                }
                sizingHolder?.sizeWindow()
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
        let tipJar = TipJar.shared
        let items = tipJar.tips
        guard index < items.count else {
            return
        }

        let t = [t1!, t2!, t3!, t4!, t5!]
        let prev = t[index].text
        t[index].text = "✅"
        view.isUserInteractionEnabled = false
        Task {
            await tipJar.purchase(items[index])
            await tipJar.waitForBusy()
            t[index].text = prev
            view.isUserInteractionEnabled = true

            if case let .error(error) = tipJar.state {
                await genericAlert(title: "There was an error completing this operation",
                                   message: error.localizedDescription)
            } else {
                await genericAlert(title: "Thank you for supporting Gladys!",
                                   message: "Thank you so much for your support, it means a lot, and it ensures that Gladys will keep receiving improvements and features in the future.")
            }
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
