//
//  RoundedBackground.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 06/06/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import UIKit

struct BackgroundSelectionEvent {
    let scene: UIWindowScene?
    let frame: CGRect?
    let name: String?
}

final class SectionBackground: UICollectionReusableView {}

final class SquareBackground: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .g_expandedSection
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
