//
//  DimView.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 24/09/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

class DimView: UIView, UIDropInteractionDelegate {
	init() {
		super.init(frame: .zero)
		let t = UITapGestureRecognizer(target: self, action: #selector(tapped))
		addGestureRecognizer(t)
		addInteraction(UIDropInteraction(delegate: self))
		if PersistedOptions.darkMode {
			backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.4036012414)
		} else {
			backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.09902076199)
		}
		alpha = 0
		UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut, animations: {
			self.alpha = 1
		}, completion: nil)
	}
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	@objc private func tapped() {
		ViewController.shared.dismissAnyPopOver()
	}
	func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
		ViewController.shared.resetForDragEntry(session: session)
	}
	func dismiss() {
		UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut, animations: {
			self.alpha = 0
		}, completion: { finished in
			self.removeFromSuperview()
		})
	}
}
