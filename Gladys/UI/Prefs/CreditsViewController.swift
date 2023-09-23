import GladysUIKit
import UIKit

final class CreditsViewController: GladysViewController {
    @IBOutlet private var scrollView: UIScrollView!

    @IBAction private func authorSelected(_: UIButton) {
        UIApplication.shared.open(URL(string: "http://bru.build")!)
    }

    @IBAction private func swiftSoupSelected(_: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/scinfu/SwiftSoup")!)
    }

    @IBAction private func zipSelected(_: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/weichsel/ZIPFoundation")!)
    }

    @IBAction private func callbackSelected(_: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/phimage/CallbackURLKit")!)
    }

    @IBAction private func lintSelected(_: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/realm/SwiftLint")!)
    }

    @IBAction private func formatSelected(_: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/nicklockwood/SwiftFormat")!)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let sizingHolder else {
            return
        }
        preferredContentSize = scrollView.contentSize
        sizingHolder.sizeWindow()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sizingHolder?.sizeWindow()
    }
}
