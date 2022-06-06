//
//  UIView+Extensions.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 11/02/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit

extension UIView {
    func cover(with view: UIView, insets: UIEdgeInsets = .zero) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
        ])
    }

    func coverUnder(with view: UIView, insets: UIEdgeInsets = .zero) {
        view.translatesAutoresizingMaskIntoConstraints = false
        superview?.insertSubview(view, belowSubview: self)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
        ])
    }

    func center(on parentView: UIView, offset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: parentView.centerXAnchor),
            centerYAnchor.constraint(equalTo: parentView.centerYAnchor, constant: offset)
        ])
    }

    static func animate(animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: animations, completion: completion)
    }
}
