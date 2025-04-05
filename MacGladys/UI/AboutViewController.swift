import AppKit
import GladysAppKit
import GladysUI
import StoreKit

final class AboutViewController: NSViewController {
    @IBOutlet private var tip1: NSView!
    @IBOutlet private var tip2: NSView!
    @IBOutlet private var tip3: NSView!
    @IBOutlet private var tip4: NSView!
    @IBOutlet private var tip5: NSView!

    @IBOutlet private var f1: NSTextField!
    @IBOutlet private var f2: NSTextField!
    @IBOutlet private var f3: NSTextField!
    @IBOutlet private var f4: NSTextField!
    @IBOutlet private var f5: NSTextField!

    @IBOutlet private var l1: NSTextField!
    @IBOutlet private var l2: NSTextField!
    @IBOutlet private var l3: NSTextField!
    @IBOutlet private var l4: NSTextField!
    @IBOutlet private var l5: NSTextField!

    @IBOutlet private var supportStack: NSStackView!
    @IBOutlet private var versionLabel: NSTextField!

    @IBOutlet private var credits: NSTextView!
    @IBOutlet private var creditsContainer: NSScrollView!

    override func viewDidLoad() {
        super.viewDidLoad()

        if let i = Bundle.main.infoDictionary,
           let v = i["CFBundleShortVersionString"] as? String,
           let b = i["CFBundleVersion"] as? String {
            versionLabel.stringValue = "v\(v) (\(b))"
        }

        for t in [tip1!, tip2!, tip3!, tip4!, tip5!] {
            t.wantsLayer = true
            t.layer?.borderWidth = 1
            t.layer?.borderColor = NSColor.systemGray.cgColor
            t.layer?.cornerRadius = 8

            let tap = NSClickGestureRecognizer(target: self, action: #selector(clicked(_:)))
            t.addGestureRecognizer(tap)
        }

        supportStack.isHidden = true

        Task {
            await TipJar.shared.setupIfNeeded()

            let fetchedProducts = TipJar.shared.tips.compactMap(\.fetchedProduct)
            guard fetchedProducts.count >= 5 else { return }

            l1.stringValue = " " + fetchedProducts[0].displayPrice + " "
            l2.stringValue = " " + fetchedProducts[1].displayPrice + " "
            l3.stringValue = " " + fetchedProducts[2].displayPrice + " "
            l4.stringValue = " " + fetchedProducts[3].displayPrice + " "
            l5.stringValue = " " + fetchedProducts[4].displayPrice + " "

            supportStack.animator().isHidden = false
        }

        // no clue why this isn't picked up automatically
        if view.effectiveAppearance.bestMatch(from: [.darkAqua]) == .darkAqua {
            credits.setTextColor(.lightGray, range: NSRange(location: 0, length: credits.attributedString().length))
            credits.backgroundColor = NSColor(white: 0, alpha: 0.5)
        }
    }

    private func purchase(sender: NSView, index: Int) {
        let tipJar = TipJar.shared
        let items = tipJar.tips
        guard index < items.count else {
            return
        }

        let f = [f1!, f2!, f3!, f4!, f5!]
        let prev = f[index].stringValue
        f[index].stringValue = "✅"
        sender.gestureRecognizers.forEach { $0.isEnabled = false }
        Task {
            await tipJar.purchase(items[index])
            await tipJar.waitForBusy()
            f[index].stringValue = prev
            sender.gestureRecognizers.forEach { $0.isEnabled = true }

            if case let .error(error) = tipJar.state {
                await genericAlert(title: "There was an error completing this operation",
                                   message: error.localizedDescription,
                                   windowOverride: view.window)
            } else {
                await genericAlert(title: "Thank you for supporting Gladys!",
                                   message: "Thank you so much for your support, it means a lot, and it ensures that Gladys will keep receiving improvements and features in the future.",
                                   windowOverride: view.window)
            }
        }
    }

    @objc private func clicked(_ recognizer: NSClickGestureRecognizer) {
        let tipJar = TipJar.shared
        let items = tipJar.tips
        if items.count < 4 {
            return
        }

        if recognizer.view == tip1 {
            purchase(sender: tip1, index: 0)

        } else if recognizer.view == tip2 {
            purchase(sender: tip2, index: 1)

        } else if recognizer.view == tip3 {
            purchase(sender: tip3, index: 2)

        } else if recognizer.view == tip4 {
            purchase(sender: tip4, index: 3)

        } else if recognizer.view == tip5 {
            purchase(sender: tip5, index: 4)
        }
    }
}
