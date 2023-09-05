import GladysCommon
import GladysUI
import GladysUIKit
import Minions
import UIKit

final class VisionSettingsController: GladysViewController, WindowSizing {
    private let viewControllers = {
        let prefs = UIStoryboard(name: "Preferences", bundle: nil)
        return ["importExportNav", "syncNav", "optionsNav", "helpNav", "aboutNav"].map {
            prefs.instantiateViewController(withIdentifier: $0) as! UINavigationController
        }
    }()

    private var buttonStack: UIView!
    private var buttons: [UIButton]!

    override func viewDidLoad() {
        super.viewDidLoad()

        viewControllers[2].isNavigationBarHidden = true

        sendNotification(name: .PreferencesOpen, object: nil)
        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(otherPrefsOpened), name: .PreferencesOpen, object: nil)

        var index = 0
        let fillImage = UIImage.block(color: .black.withAlphaComponent(0.1), size: CGSize(width: 1, height: 1))
        let clearImage = UIImage.block(color: .clear, size: CGSize(width: 1, height: 1))
        buttons = viewControllers.compactMap(\.tabBarItem).map { tabItem in
            let i = index
            let button = UIButton(type: .system)

            button.setBackgroundImage(fillImage, for: .normal)
            button.setImage(tabItem.image?.withTintColor(.g_colorTint, renderingMode: .alwaysOriginal), for: .normal)

            button.setBackgroundImage(clearImage, for: .selected)
            button.setImage(tabItem.image?.withRenderingMode(.alwaysTemplate), for: .selected)

            button.addAction(UIAction(handler: #weakSelf { _ in
                selectTab(i)
            }), for: .touchUpInside)
            index += 1
            return button
        }

        let stack = UIStackView(arrangedSubviews: buttons)
        stack.distribution = .fillEqually
        stack.spacing = 0

        let bar = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 80))
        stack.frame = bar.bounds
        bar.cover(with: stack)
        bar.autoresizingMask = [.flexibleWidth]
        view.addSubview(bar)

        buttonStack = bar

        selectTab(PersistedOptions.lastSelectedPreferencesTab)
    }

    @objc private func otherPrefsOpened() {
        dismiss(animated: true)
    }

    private var currentVc: UIViewController?

    private func selectTab(_ index: Int) {
        if let currentVc {
            removeChildController(currentVc)
        }

        PersistedOptions.lastSelectedPreferencesTab = index

        for i in 0 ..< buttons.count {
            buttons[i].isSelected = i == index
        }

        let vc = viewControllers[index]
        currentVc = vc
        addChildController(vc, to: view, insets: UIEdgeInsets(top: -80, left: 0, bottom: 0, right: 0))

        view.bringSubviewToFront(buttonStack)

        if isVisible {
            sizeWindow()
        }
    }

    private var isVisible = false

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        sizeWindow()
        isVisible = true
    }

    func sizeWindow() {
        guard let n = currentVc as? UINavigationController, let v = n.topViewController else {
            return
        }
        n.view.layoutIfNeeded()
        var size = CGSize(width: 400, height: 80)
        if !n.isNavigationBarHidden {
            size.height += n.navigationBar.frame.height
        }
        if let s = v.view.subviews.first as? UIScrollView {
            size.height += s.contentSize.height
        }
        preferredContentSize = size
    }
}
