import GladysCommon
import UIKit

final class VisionSettingsController: UIViewController {
    private let viewControllers = {
        let prefs = UIStoryboard(name: "Preferences", bundle: nil)
        return ["importExportNav", "syncNav", "optionsNav", "helpNav", "aboutNav"].map {
            prefs.instantiateViewController(withIdentifier: $0)
        }
    }()

    private var buttonStack: UIView!
    private var buttons: [UIButton]!

    override func viewDidLoad() {
        super.viewDidLoad()

        sendNotification(name: .PreferencesOpen, object: nil)
        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(otherPrefsOpened), name: .PreferencesOpen, object: nil)

        preferredContentSize = CGSize(width: 360, height: 680)

        var index = 0
        buttons = viewControllers.compactMap(\.tabBarItem).map { tabItem in
            let i = index
            let button = UIButton(type: .system)
            button.setImage(tabItem.image?.withRenderingMode(.alwaysTemplate), for: .normal)
            button.setImage(tabItem.image?.withTintColor(.g_colorTint, renderingMode: .alwaysOriginal), for: .selected)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                selectTab(i)
            }, for: .touchUpInside)
            index += 1
            return button
        }

        let stack = UIStackView(arrangedSubviews: buttons)
        stack.distribution = .fillEqually
        stack.spacing = 0

        let bar = UIView(frame: CGRect(x: 0, y: view.bounds.height - 80, width: view.bounds.width, height: 80))
        bar.backgroundColor = .secondarySystemBackground
        stack.frame = bar.bounds
        bar.cover(with: stack)
        bar.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
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
        addChildController(vc, to: view, insets: UIEdgeInsets(top: 0, left: 0, bottom: -80, right: 0))

        view.bringSubviewToFront(buttonStack)
    }
}
