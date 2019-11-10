//
//  GladysViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 19/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

class GladysViewController: UIViewController {

	enum ActionLocation {
		case none, left, right
	}
	var doneButtonLocation = ActionLocation.none
    var windowButtonLocation = ActionLocation.none
    var dismissOnNewWindow = true
    var autoConfigureButtons = false

	var initialAccessibilityElement: UIView {
		return navigationController?.navigationBar ?? view
	}

	func focusInitialAccessibilityElement() {
		UIAccessibility.post(notification: .layoutChanged, argument: initialAccessibilityElement)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if popoverPresenter != nil {
			UIAccessibility.post(notification: .layoutChanged, argument: initialAccessibilityElement)
		}
	}
        
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil {
            updateButtons()
        }
    }

	private var popoverPresenter: UIViewController? {
		return popoverPresentationController?.presentingViewController ?? navigationController?.popoverPresentationController?.presentingViewController
	}
    
    override func viewDidLoad() {
        autoConfigureButtons = isAccessoryWindow
        super.viewDidLoad()
        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(updateButtons), name: .MultipleWindowModeChange, object: nil)
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
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateButtons()
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
        let mainWindowSession = UIApplication.shared.openSessions.first { $0.stateRestorationActivity == nil }
        UIApplication.shared.requestSceneSessionActivation(mainWindowSession, userActivity: nil, options: options) { error in
            log("Error opening new window: \(error.localizedDescription)")
        }
    }
    
    private var scrollTimer: GladysTimer?
	private var scrollLink: CADisplayLink?
	private var scrollView: UIScrollView?

	override var keyCommands: [UIKeyCommand]? {
		var a = [
			UIKeyCommand(title: "Scroll Down", action: #selector(scrollDown), input: UIKeyCommand.inputUpArrow),
			UIKeyCommand(title: "Scroll Up", action: #selector(scrollUp), input: UIKeyCommand.inputDownArrow),
		]
		if self.popoverPresenter != nil {
            let w = UIKeyCommand.makeCommand(input: "w", modifierFlags: .command, action: #selector(done), title: "Close This View")
			a.insert(w, at: 0)
		}
		return a
	}

	@objc private func scrollUp() {
		startScroll(#selector(scrollLineUp))
	}

	@objc private func scrollDown() {
		startScroll(#selector(scrollLineDown))
	}

	private func startScroll(_ selector: Selector) {
		scrollLink?.invalidate()
		guard let scr = view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView else { return }
		scrollView = scr
		scrollLink = CADisplayLink(target: self, selector: selector)
		scrollLink!.add(to: RunLoop.main, forMode: .common)
		scrollTimer = GladysTimer(interval: 0.4) {
			self.scrollLink?.invalidate()
			self.scrollLink = nil
			self.scrollView = nil
		}
	}

	@objc private func scrollLineUp() {
		if let firstScrollView = scrollView {
			var newPos = firstScrollView.contentOffset
			let maxY = (firstScrollView.contentSize.height - firstScrollView.bounds.size.height) + firstScrollView.adjustedContentInset.bottom
			newPos.y = min(firstScrollView.contentOffset.y+8, maxY)
			firstScrollView.setContentOffset(newPos, animated: false)
		}
	}

	@objc private func scrollLineDown() {
		if let firstScrollView = scrollView {
			var newPos = firstScrollView.contentOffset
			newPos.y = max(newPos.y-8, -firstScrollView.adjustedContentInset.top)
			firstScrollView.setContentOffset(newPos, animated: false)
		}
	}

	private func showDone(_ show: Bool) {
        showButton(show, location: doneButtonLocation, button: doneButton)
	}
    
    private func showWindow(_ show: Bool) {
        showButton(show && isAccessoryWindow, location: windowButtonLocation, button: mainWindowButton)
        showButton(show && !isAccessoryWindow, location: windowButtonLocation, button: newWindowButton)
    }

    private func showButton(_ show: Bool, location: ActionLocation, button: UIBarButtonItem) {
        let tag = button.tag
        switch location {
        case .left:
            var leftItems = navigationItem.leftBarButtonItems ?? []
            if show && !leftItems.contains(where: { $0.tag == tag }) {
                leftItems.append(button)
                navigationItem.leftBarButtonItems = leftItems
            } else if !show {
                navigationItem.leftBarButtonItems?.removeAll { $0.tag == tag }
            }
        case .right:
            var rightItems = navigationItem.rightBarButtonItems ?? []
            if show && !rightItems.contains(where: { $0.tag == tag }) {
                rightItems.append(button)
                navigationItem.rightBarButtonItems = rightItems
            } else if !show {
                navigationItem.rightBarButtonItems?.removeAll { $0.tag == tag }
            }
        case .none:
            navigationItem.leftBarButtonItems?.removeAll { $0.tag == tag }
            navigationItem.rightBarButtonItems?.removeAll { $0.tag == tag }
        }
    }
    
    @objc private func updateButtons() {
        if autoConfigureButtons {
            if SceneDelegate.openCount > 1 {
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
            
        } else if (popoverPresentationController?.adaptivePresentationStyle.rawValue ?? 0) == -1 { // hovering
            if traitCollection.horizontalSizeClass == .compact {
                showDone(false)

            } else {
                showDone(traitCollection.verticalSizeClass == .compact)
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
        return (navigationController?.viewIfLoaded ?? viewIfLoaded)?.window?.windowScene?.isInStandaloneWindow ?? false
    }
}
