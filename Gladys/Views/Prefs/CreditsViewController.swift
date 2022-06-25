import UIKit

final class CreditsViewController: GladysViewController {
    @IBOutlet private var scrollView: UIScrollView!

    @IBAction private func authorSelected(_: UIButton) {
        UIApplication.shared.open(URL(string: "http://bru.build")!)
    }

    @IBAction private func fuziSelected(_: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/cezheng/Fuzi")!)
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
        if let tabs = tabBarController as? SelfSizingTabController {
            tabs.sizeWindow()
        }
    }
}
