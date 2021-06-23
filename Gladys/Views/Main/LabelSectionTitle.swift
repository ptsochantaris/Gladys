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
    private let topLine = UIView()
    private let bottomLine = UIView()

    static let titleStyle = UIFont.TextStyle.subheadline

    private func setup() {
        
        tintColor = .secondaryLabel
        isUserInteractionEnabled = true

        label.font = UIFont.preferredFont(forTextStyle: LabelSectionTitle.titleStyle)
        label.isUserInteractionEnabled = false
        label.textColor = .secondaryLabel
        label.highlightedTextColor = .label
        
        indicator.contentMode = .center
        let textStyle = UIImage.SymbolConfiguration(textStyle: LabelSectionTitle.titleStyle)
        indicator.highlightedImage = UIImage(systemName: "chevron.right")?.applyingSymbolConfiguration(textStyle)
        indicator.image = UIImage(systemName: "chevron.down")?.applyingSymbolConfiguration(textStyle)
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
        
        topLine.backgroundColor = UIColor(white: 1, alpha: 0.9)
        topLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topLine)

        bottomLine.backgroundColor = UIColor(white: 0, alpha: 0.3)
        bottomLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomLine)

        let pixelHeight: CGFloat = 1 / screenScale
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),

            topLine.heightAnchor.constraint(equalToConstant: pixelHeight),
            topLine.topAnchor.constraint(equalTo: topAnchor),
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -44),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 44),
            
            bottomLine.heightAnchor.constraint(equalToConstant: pixelHeight),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -44),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 44)
        ])
    }
    
    @objc private func selected() {
        NotificationCenter.default.post(name: .SectionBackgroundTapped, object: BackgroundSelectionEvent(scene: self.window?.windowScene, frame: nil, name: self.label.text))
    }
    
    func configure(with identifier: SectionIdentifier, firstSection: Bool, menuOptions: [UIMenuElement]) {
        guard let section = identifier.section else { return }
        label.text = section.name
        label.isHighlighted = section.collapsed
        indicator.isHighlighted = section.collapsed
        indicator.tintColor = section.collapsed ? .label : .secondaryLabel
        let expanded = !section.collapsed
        topLine.isHidden = expanded || firstSection
        bottomLine.isHidden = expanded
        button.menu = UIMenu(title: "Sections", image: nil, identifier: nil, options: [], children: menuOptions)
    }
}
