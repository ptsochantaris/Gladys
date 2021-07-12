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

class SectionBackground: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    func setup() {}    
}

final class SquareBackground: SectionBackground {
    override func setup() {
        super.setup()
        self.backgroundColor = .quaternarySystemFill
    }
}
