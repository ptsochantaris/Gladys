//
//  LabelSectionTitle.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 06/06/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import UIKit

struct SectionIdentifier: Hashable {
    let section: ModelFilterContext.LabelToggle
    let expanded: Bool
}

struct ItemIdentifier: Hashable {
    let section: ModelFilterContext.LabelToggle
    let uuid: UUID
}

final class LabelSectionTitle: UICollectionReusableView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private let label = UILabel()
    private let indicator = UIImageView()
    private let button = UIButton(type: .custom)
    private var tappedCompletion: (() -> Void)?

    private func setup() {
        label.textColor = .secondaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.isUserInteractionEnabled = false
        
        indicator.contentMode = .center
        indicator.image = UIImage(systemName: "chevron.down")
        indicator.highlightedImage = UIImage(systemName: "chevron.up")
        indicator.isUserInteractionEnabled = false
        
        let stack = UIStackView(arrangedSubviews: [label, indicator])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.tappedCompletion?()
        }, for: .touchUpInside)
        addSubview(button)
        
        let guide = layoutMarginsGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: guide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            
            indicator.heightAnchor.constraint(equalTo: indicator.widthAnchor),
            
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    func configure(with identifier: SectionIdentifier, topSpace: CGFloat, tapCompletion: @escaping () -> Void) {
        layoutMargins = UIEdgeInsets(top: topSpace, left: 4, bottom: 0, right: 4)
        label.text = identifier.section.name
        tappedCompletion = tapCompletion
        indicator.isHighlighted = identifier.expanded
    }
    
    var menuOptions: [UIMenuElement]? {
        didSet {
            if let menuOptions = menuOptions {
                button.menu = UIMenu(title: "Sections", image: nil, identifier: nil, options: [], children: menuOptions)
            } else {
                button.menu = nil
            }
        }
    }
}
