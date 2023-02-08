import GladysCommon
import UIKit

protocol GladysViewDelegate: AnyObject {
    func movedToWindow()
}

final class GladysView: UIView {
    weak var delegate: GladysViewDelegate?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            delegate?.movedToWindow()
        }
    }
}

class GladysViewController: UIViewController, GladysViewDelegate {
    enum ActionLocation {
        case none, left, right
    }

    var doneButtonLocation = ActionLocation.none
    var windowButtonLocation = ActionLocation.none
    var dismissOnNewWindow = true
    var autoConfigureButtons = false
    var firstAppearance = true

    var initialAccessibilityElement: UIView {
        navigationController?.navigationBar ?? view
    }

    func focusInitialAccessibilityElement() {
        UIAccessibility.post(notification: .layoutChanged, argument: initialAccessibilityElement)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        firstAppearance = false
        if popoverPresenter != nil {
            UIAccessibility.post(notification: .layoutChanged, argument: initialAccessibilityElement)
        }
    }

    private var popoverPresenter: UIViewController? {
        popoverPresentationController?.presentingViewController ?? navigationController?.popoverPresentationController?.presentingViewController
    }

    override func viewDidLoad() {
        autoConfigureButtons = isAccessoryWindow
        super.viewDidLoad()
        Task {
            for await _ in NotificationCenter.default.notifications(named: .MultipleWindowModeChange) {
                updateButtons(newTraitCollection: view.traitCollection)
            }
        }
        (view as? GladysView)?.delegate = self
    }

    func movedToWindow() {
        updateButtons(newTraitCollection: view.traitCollection)
    }

    private weak var vcToFocusAfterDismissal: UIViewController?

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.isBeingDismissed ?? isBeingDismissed, let v = popoverPresenter {
            if let v = v as? UINavigationController {
                vcToFocusAfterDismissal = v.viewControllers.last
            } else {
                vcToFocusAfterDismissal = v
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let v = vcToFocusAfterDismissal {
            if let v = v as? GladysViewController {
                UIAccessibility.post(notification: .layoutChanged, argument: v.initialAccessibilityElement)
            } else {
                UIAccessibility.post(notification: .layoutChanged, argument: v.view)
            }
        }
    }

    @objc func done() {
        NotificationCenter.default.removeObserver(self) // avoid any notifications while being dismissed or if we stick around for a short while
        if isAccessoryWindow || self is ViewController, let session = (navigationController?.viewIfLoaded ?? viewIfLoaded)?.window?.windowScene?.session {
            let options = UIWindowSceneDestructionRequestOptions()
            options.windowDismissalAnimation = .standard
            UIApplication.shared.requestSceneSessionDestruction(session, options: options, errorHandler: nil)
        } else {
            dismiss(animated: true)
        }
    }

    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
        updateButtons(newTraitCollection: newCollection)
    }

    @objc private func newWindowSelected() {
        let activity = userActivity
        if dismissOnNewWindow {
            done()
        }
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = view.window?.windowScene
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: options) { error in
            log("Error opening new window: \(error.localizedDescription)")
        }
    }

    @objc private func mainWindowSelected() {
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = view.window?.windowScene
        let mainWindowSession = UIApplication.shared.openSessions.first { $0.isMainWindow }
        UIApplication.shared.requestSceneSessionActivation(mainWindowSession, userActivity: nil, options: options) { error in
            log("Error opening new window: \(error.localizedDescription)")
        }
    }

    private func showDone(_ show: Bool) {
        showButton(show, location: doneButtonLocation, button: doneButton, priority: true)
    }

    private func showWindow(_ show: Bool) {
        showButton(show && isAccessoryWindow, location: windowButtonLocation, button: mainWindowButton, priority: false)
        showButton(show && !isAccessoryWindow, location: windowButtonLocation, button: newWindowButton, priority: false)
    }

    private func showButton(_ show: Bool, location: ActionLocation, button: UIBarButtonItem, priority: Bool) {
        let tag = button.tag
        switch location {
        case .left:
            var leftItems = navigationItem.leftBarButtonItems ?? []
            if show, !leftItems.contains(where: { $0.tag == tag }) {
                if priority {
                    leftItems.insert(button, at: 0)
                } else {
                    leftItems.append(button)
                }
                navigationItem.leftBarButtonItems = leftItems
            } else if !show {
                navigationItem.leftBarButtonItems?.removeAll { $0.tag == tag }
            }
        case .right:
            var rightItems = navigationItem.rightBarButtonItems ?? []
            if show, !rightItems.contains(where: { $0.tag == tag }) {
                if priority {
                    rightItems.insert(button, at: 0)
                } else {
                    rightItems.append(button)
                }
                navigationItem.rightBarButtonItems = rightItems
            } else if !show {
                navigationItem.rightBarButtonItems?.removeAll { $0.tag == tag }
            }
        case .none:
            navigationItem.leftBarButtonItems?.removeAll { $0.tag == tag }
            navigationItem.rightBarButtonItems?.removeAll { $0.tag == tag }
        }
        navigationController?.navigationBar.setNeedsLayout()
    }

    func updateButtons(newTraitCollection: UITraitCollection) {
        if autoConfigureButtons {
            if Singleton.shared.openCount > 1 {
                doneButtonLocation = .right
                windowButtonLocation = .none
            } else {
                doneButtonLocation = .none
                windowButtonLocation = .right
            }
        }

        if doneButtonLocation == .none {
            showDone(false)

        } else if UIAccessibility.isVoiceOverRunning || isAccessoryWindow {
            showDone(true)

        } else if isHovering { // hovering
            if newTraitCollection.horizontalSizeClass == .compact {
                showDone(false)

            } else {
                showDone(newTraitCollection.verticalSizeClass == .compact)
            }

        } else { // full window?
            showDone(popoverPresentationController == nil || phoneMode)
        }

        let w = windowButtonLocation != .none && UIApplication.shared.supportsMultipleScenes
        showWindow(w)
    }

    private lazy var doneButton: UIBarButtonItem = {
        let b = makeDoneButton(target: self, action: #selector(done))
        b.tag = 10925
        return b
    }()

    private lazy var mainWindowButton: UIBarButtonItem = {
        let b = UIBarButtonItem(title: "Main Window", style: .plain, target: self, action: #selector(mainWindowSelected))
        b.image = UIImage(systemName: "square.grid.2x2")
        b.tag = 10924
        return b
    }()

    private lazy var newWindowButton: UIBarButtonItem = {
        let b = UIBarButtonItem(title: "New Window", style: .plain, target: self, action: #selector(newWindowSelected))
        b.image = UIImage(systemName: "uiwindow.split.2x1")
        b.tag = 10923
        return b
    }()

    // MARK: scrolling

    private final class ScrollInfo {
        let scrollLink: CADisplayLink
        let scrollView: UIScrollView

        init(scrollView: UIScrollView, target: AnyObject, selector: Selector) {
            self.scrollView = scrollView
            scrollLink = CADisplayLink(target: target, selector: selector)
            scrollLink.add(to: RunLoop.main, forMode: .common)
        }

        deinit {
            scrollLink.invalidate()
        }
    }

    private var scrollInfo: ScrollInfo?

    var explicitScrolling = false

    override var keyCommands: [UIKeyCommand]? {
        var a = [UIKeyCommand]()
        if explicitScrolling {
            a.append(UIKeyCommand(title: "Scroll Down", action: #selector(scrollDown), input: UIKeyCommand.inputUpArrow))
            a.append(UIKeyCommand(title: "Scroll Up", action: #selector(scrollUp), input: UIKeyCommand.inputDownArrow))
        }
        a.append(UIKeyCommand(title: "Page Down", action: #selector(pageDown), input: UIKeyCommand.inputPageDown))
        a.append(UIKeyCommand(title: "Page Up", action: #selector(pageUp), input: UIKeyCommand.inputPageUp))
        let itemsToCheck = (navigationItem.leftBarButtonItems ?? []) + (navigationItem.rightBarButtonItems ?? [])
        if itemsToCheck.contains(doneButton) {
            a.append(UIKeyCommand(title: "Close Window", action: #selector(done), input: "w", modifierFlags: .command))
        }
        if itemsToCheck.contains(newWindowButton) {
            a.append(UIKeyCommand(title: "New Window", action: #selector(newWindowSelected), input: "n", modifierFlags: .command))
        }
        if itemsToCheck.contains(mainWindowButton) {
            a.append(UIKeyCommand(title: "Main Window", action: #selector(mainWindowSelected), input: "n", modifierFlags: .command))
        }
        if popoverPresenter != nil {
            let esc = UIKeyCommand.makeCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(done), title: "Close Popup")
            a.insert(esc, at: 0)
        }
        return a
    }

    @objc private func scrollUp() {}

    @objc private func scrollDown() {}

    @objc private func pageDown() {
        guard let scr = view.subviews.compactMap({ $0 as? UIScrollView }).lazy.first else { return }
        var currentOffset = scr.contentOffset
        currentOffset.y = min(currentOffset.y + scr.bounds.height, scr.contentSize.height - scr.bounds.height + scr.adjustedContentInset.bottom)
        scr.setContentOffset(currentOffset, animated: true)
    }

    @objc private func pageUp() {
        guard let scr = view.subviews.compactMap({ $0 as? UIScrollView }).lazy.first else { return }
        var currentOffset = scr.contentOffset
        currentOffset.y = max(currentOffset.y - scr.bounds.height, -scr.adjustedContentInset.top - 55)
        scr.setContentOffset(currentOffset, animated: true)
    }

    private func pressesDone(_ presses: Set<UIPress>) -> Bool {
        if explicitScrolling {
            let code = presses.first?.key?.keyCode
            if code == UIKeyboardHIDUsage.keyboardUpArrow || code == UIKeyboardHIDUsage.keyboardDownArrow {
                scrollInfo = nil
                return true
            }
        }
        return false
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if explicitScrolling, let scr = view.subviews.compactMap({ $0 as? UIScrollView }).lazy.first {
            let code = presses.first?.key?.keyCode
            if code == UIKeyboardHIDUsage.keyboardUpArrow {
                scrollInfo = ScrollInfo(scrollView: scr, target: self, selector: #selector(scrollLineDown))
                return
            } else if code == UIKeyboardHIDUsage.keyboardDownArrow {
                scrollInfo = ScrollInfo(scrollView: scr, target: self, selector: #selector(scrollLineUp))
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !pressesDone(presses) {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !pressesDone(presses) {
            super.pressesCancelled(presses, with: event)
        }
    }

    @objc private func scrollLineUp() {
        if let firstScrollView = scrollInfo?.scrollView {
            var newPos = firstScrollView.contentOffset
            let maxY = (firstScrollView.contentSize.height - firstScrollView.bounds.size.height) + firstScrollView.adjustedContentInset.bottom
            newPos.y = min(firstScrollView.contentOffset.y + 12, maxY)
            firstScrollView.contentOffset = newPos
        }
    }

    @objc private func scrollLineDown() {
        if let firstScrollView = scrollInfo?.scrollView {
            var newPos = firstScrollView.contentOffset
            newPos.y = max(newPos.y - 12, -firstScrollView.adjustedContentInset.top - 1)
            firstScrollView.contentOffset = newPos
        }
    }

    func confirm(title: String, message: String, action: String, cancel: String) async -> Bool {
        var continuation: CheckedContinuation<Bool, Never>?

        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: action, style: .default) { _ in
            continuation?.resume(returning: true)
        })
        a.addAction(UIAlertAction(title: cancel, style: .cancel) { _ in
            continuation?.resume(returning: false)
        })
        present(a, animated: true)

        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            continuation = c
        }
    }
}
