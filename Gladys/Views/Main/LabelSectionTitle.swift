//
//  LabelSectionTitle.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 06/06/2021.
//  Copyright © 2021 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelSectionTitle: UICollectionReusableView {
    static let height: CGFloat = 50
    
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
    static let titleStyle = UIFont.TextStyle.subheadline

    override func tintColorDidChange() {
        super.tintColorDidChange()
        label.textColor = self.tintColor
    }
    
    private func setup() {
        self.tintColor = .secondaryLabel
        self.isUserInteractionEnabled = true
                
        label.font = UIFont.preferredFont(forTextStyle: LabelSectionTitle.titleStyle)
        label.isUserInteractionEnabled = false
        
        indicator.contentMode = .center
        let textStyle = UIImage.SymbolConfiguration(textStyle: LabelSectionTitle.titleStyle)
        indicator.image = UIImage(systemName: "chevron.right")?.applyingSymbolConfiguration(textStyle)
        indicator.highlightedImage = UIImage(systemName: "chevron.down")?.applyingSymbolConfiguration(textStyle)
        indicator.isUserInteractionEnabled = false
        
        let stack = UIStackView(arrangedSubviews: [label, indicator])
        stack.isUserInteractionEnabled = false
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        
        button.addTarget(self, action: #selector(selected), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        
        let guide = layoutMarginsGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: guide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    @objc private func selected() {
        NotificationCenter.default.post(name: .SectionBackgroundTapped, object: BackgroundSelectionEvent(scene: self.window?.windowScene, frame: nil, name: self.label.text))
    }
    
    func configure(with identifier: SectionIdentifier, menuOptions: [UIMenuElement]) {
        guard let section = identifier.section else { return }
        label.text = section.name
        indicator.isHighlighted = !section.collapsed
        layoutMargins = UIEdgeInsets(top: 8, left: 5, bottom: 0, right: 6)
        button.menu = UIMenu(title: "Sections", image: nil, identifier: nil, options: [], children: menuOptions)
    }
}
