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

	private var popoverPresenter: UIViewController? {
		return popoverPresentationController?.presentingViewController ?? navigationController?.popoverPresentationController?.presentingViewController
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
        if isInStandaloneWindow, let session = (navigationController?.viewIfLoaded ?? viewIfLoaded)?.window?.windowScene?.session {
            let options = UIWindowSceneDestructionRequestOptions()
            options.windowDismissalAnimation = .standard
            UIApplication.shared.requestSceneSessionDestruction(session, options: options, errorHandler: nil)
        } else {
            dismiss(animated: true)
        }
	}
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateButtons(traits: traitCollection)

    }
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        updateButtons(traits: newCollection)
    }

    private func updateButtons(traits: UITraitCollection) {
        if windowButtonLocation != .none && traits.userInterfaceIdiom == .pad {
            showWindow(true)
        }
        
        if doneButtonLocation != .none {
            if UIAccessibility.isVoiceOverRunning || isInStandaloneWindow {
                showDone(true)
                return
            }
            
            let s = popoverPresentationController?.adaptivePresentationStyle.rawValue ?? 0
            if s == -1 { // hovering
                if traits.horizontalSizeClass == .compact {
                    showDone(false)
                } else {
                    showDone(traits.verticalSizeClass == .compact)
                }
            } else { // full window?
                showDone(popoverPresentationController == nil || phoneMode || isInStandaloneWindow)
            }
        }
    }
         
    @objc private func newWindowSelected() {
        let activity = userActivity
        done()
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
        let n1 = UIBarButtonItem(title: "Main Window", style: .plain, target: self, action: #selector(mainWindowSelected))
        n1.image = UIImage(systemName: "square.grid.2x2")
        showButton(isInStandaloneWindow, location: windowButtonLocation, button: n1)

        let n2 = UIBarButtonItem(title: "New Window", style: .plain, target: self, action: #selector(newWindowSelected))
        n2.image = UIImage(systemName: "uiwindow.split.2x1")
        showButton(!isInStandaloneWindow, location: windowButtonLocation, button: n2)
    }

    private func showButton(_ show: Bool, location: ActionLocation, button: UIBarButtonItem) {
        switch location {
        case .left:
            var leftItems = navigationItem.leftBarButtonItems ?? []
            if show && !leftItems.contains(button) {
                leftItems.insert(button, at: 0)
                navigationItem.leftBarButtonItems = leftItems
            } else if !show && leftItems.contains(button) {
                navigationItem.leftBarButtonItems = leftItems.filter { $0 != button }
            }
        case .right:
            var rightItems = navigationItem.rightBarButtonItems ?? []
            if show && !rightItems.contains(button) {
                rightItems.insert(button, at: 0)
                navigationItem.rightBarButtonItems = rightItems
            } else if !show && rightItems.contains(button) {
                navigationItem.rightBarButtonItems = rightItems.filter { $0 != button }
            }
        case .none:
            break
        }
    }
    
	private lazy var doneButton: UIBarButtonItem = {
        return makeDoneButton(target: self, action: #selector(done))
	}()
    
    var isInStandaloneWindow: Bool {
        return (navigationController?.viewIfLoaded ?? viewIfLoaded)?.window?.windowScene?.isInStandaloneWindow ?? false
    }
}
