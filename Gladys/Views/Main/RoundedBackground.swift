//
//  RoundedBackground.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 06/06/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import UIKit

class SectionBackground: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        self.addGestureRecognizer(tap)
    }
    
    @objc private func tapped(tap: UITapGestureRecognizer) {
        NotificationCenter.default.post(name: .SectionBackgroundTapped, object: tap.view?.frame)
    }
}

final class RoundedBackground: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
        
    @objc private func tapped(tap: UITapGestureRecognizer) {
        NotificationCenter.default.post(name: .SectionBackgroundTapped, object: tap.view?.frame)
    }
    
    private func setup() {
        self.backgroundColor = .quaternarySystemFill
        self.layer.cornerRadius = self.traitCollection.horizontalSizeClass == .compact ? 0 : 10
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        self.addGestureRecognizer(tap)
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.layer.cornerRadius = self.traitCollection.horizontalSizeClass == .compact ? 0 : 10
    }
}
