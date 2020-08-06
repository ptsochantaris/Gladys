//
//  GladysViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 19/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

protocol GladysViewDelegate: class {
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
		return navigationController?.navigationBar ?? view
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
		return popoverPresentationController?.presentingViewController ?? navigationController?.popoverPresentationController?.presentingViewController
	}
    
    override func viewDidLoad() {
        autoConfigureButtons = isAccessoryWindow
        super.viewDidLoad()
        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(multipleWindowModeChange), name: .MultipleWindowModeChange, object: nil)
        (view as? GladysView)?.delegate = self
    }
    
    @objc private func multipleWindowModeChange() {
        updateButtons(newTraitCollection: view.traitCollection)
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
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

	@objc func done() {
        NotificationCenter.default.removeObserver(self) // avoid any notifications while being dismissed or if we stick around for a short while
        if (isAccessoryWindow || self is ViewController), let session = (navigationController?.viewIfLoaded ?? viewIfLoaded)?.window?.windowScene?.session {
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
        #if targetEnvironment(macCatalyst)
            if doneButtonLocation != ActionLocation.right {
                showButton(show, location: doneButtonLocation, button: doneButton, priority: true)
            }
        #else
            showButton(show, location: doneButtonLocation, button: doneButton, priority: true)
        #endif
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
            if show && !leftItems.contains(where: { $0.tag == tag }) {
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
            if show && !rightItems.contains(where: { $0.tag == tag }) {
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
    
    var isHovering: Bool {
        return (popoverPresentationController?.adaptivePresentationStyle.rawValue ?? 0) == -1
    }
    
    private func updateButtons(newTraitCollection: UITraitCollection) {
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
            showDone(popoverPresentationController == nil || phoneMode || isAccessoryWindow)
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
    
    var isAccessoryWindow: Bool {
        return (navigationController?.viewIfLoaded ?? viewIfLoaded)?.window?.windowScene?.isAccessoryWindow ?? false
    }
    
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

    override var keyCommands: [UIKeyCommand]? {
        var a = [UIKeyCommand]()
        if #available(iOS 13.4, *), isFirstResponder {
            a.append(UIKeyCommand(title: "Scroll Down", action: #selector(scrollDown), input: UIKeyCommand.inputUpArrow))
            a.append(UIKeyCommand(title: "Scroll Up", action: #selector(scrollUp), input: UIKeyCommand.inputDownArrow))
            a.append(UIKeyCommand(title: "Page Down", action: #selector(pageDown), input: UIKeyCommand.inputPageDown))
            a.append(UIKeyCommand(title: "Page Up", action: #selector(pageUp), input: UIKeyCommand.inputPageUp))
        }
        if self.popoverPresenter != nil {
            let w = UIKeyCommand.makeCommand(input: "w", modifierFlags: .command, action: #selector(done), title: "Close Popup")
            a.insert(w, at: 0)
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
        if #available(iOS 13.4, *), isFirstResponder {
            let code = presses.first?.key?.keyCode
            if code == UIKeyboardHIDUsage.keyboardUpArrow || code == UIKeyboardHIDUsage.keyboardDownArrow {
                scrollInfo = nil
                return true
            }
        }
        return false
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if #available(iOS 13.4, *), isFirstResponder, let scr = view.subviews.compactMap({ $0 as? UIScrollView }).lazy.first {
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
}
