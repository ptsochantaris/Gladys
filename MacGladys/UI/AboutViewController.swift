import AppKit
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

    private var tipJar: TipJar?
    private var tipItems: [SKProduct]?

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
        tipJar = TipJar { [weak self] items, _ in
            guard let s = self, let items, items.count > 4 else { return }

            s.tipItems = items
            s.l1.stringValue = " " + (items[0].regularPrice ?? "") + " "
            s.l2.stringValue = " " + (items[1].regularPrice ?? "") + " "
            s.l3.stringValue = " " + (items[2].regularPrice ?? "") + " "
            s.l4.stringValue = " " + (items[3].regularPrice ?? "") + " "
            s.l5.stringValue = " " + (items[4].regularPrice ?? "") + " "

            s.supportStack.animator().isHidden = false
        }

        // no clue why this isn't picked up automatically
        if view.effectiveAppearance.bestMatch(from: [.darkAqua]) == .darkAqua {
            credits.setTextColor(.lightGray, range: NSRange(location: 0, length: credits.attributedString().length))
            credits.backgroundColor = NSColor(white: 0, alpha: 0.5)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        tipJar?.aboutWindow = view.window
    }

    private func purchase(sender: NSView, index: Int) {
        guard let tipJar, let items = tipItems else { return }

        let f = [f1!, f2!, f3!, f4!, f5!]
        let prev = f[index].stringValue
        f[index].stringValue = "✅"
        sender.gestureRecognizers.forEach { $0.isEnabled = false }
        tipJar.requestItem(items[index]) {
            f[index].stringValue = prev
            sender.gestureRecognizers.forEach { $0.isEnabled = true }
        }
    }

    @objc private func clicked(_ recognizer: NSClickGestureRecognizer) {
        guard let items = tipItems, items.count > 4 else { return }

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
