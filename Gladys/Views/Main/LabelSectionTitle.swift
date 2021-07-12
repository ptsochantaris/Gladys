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
    private let showAllButton = UIButton(type: .custom)
    private let topLine = UIView()
    private let bottomLine = UIView()
    private var menuOptions = [UIMenuElement]()
    private var toggle: ModelFilterContext.LabelToggle?
    
    private weak var viewController: ViewController?
    private weak var dataSource: UICollectionViewDiffableDataSource<SectionIdentifier, ItemIdentifier>?

    static let titleStyle = UIFont.TextStyle.subheadline

    private func setup() {
        
        tintColor = .secondaryLabel
        isUserInteractionEnabled = true
        addInteraction(UIContextMenuInteraction(delegate: self))

        let labelFont = UIFont.preferredFont(forTextStyle: LabelSectionTitle.titleStyle)
        
        label.font = labelFont
        label.isUserInteractionEnabled = true
        label.textColor = .secondaryLabel
        label.highlightedTextColor = .label
        
        indicator.contentMode = .center
        let textStyle = UIImage.SymbolConfiguration(textStyle: LabelSectionTitle.titleStyle)
        indicator.highlightedImage = UIImage(systemName: "chevron.right")?.applyingSymbolConfiguration(textStyle)
        indicator.image = UIImage(systemName: "chevron.down")?.applyingSymbolConfiguration(textStyle)
        indicator.setContentHuggingPriority(.required, for: .horizontal)
        indicator.isUserInteractionEnabled = true
        
        showAllButton.titleLabel?.font = labelFont
        showAllButton.addTarget(self, action: #selector(showAllSelected), for: .touchUpInside)
        showAllButton.setContentHuggingPriority(.required, for: .horizontal)
        showAllButton.setTitleColor(UIColor.g_colorTint, for: .normal)
        addSubview(showAllButton)
        
        let labelTap = UITapGestureRecognizer(target: self, action: #selector(selected))
        label.addGestureRecognizer(labelTap)
        
        let indicatorTap = UITapGestureRecognizer(target: self, action: #selector(selected))
        indicator.addGestureRecognizer(indicatorTap)

        let stack = UIStackView(arrangedSubviews: [label, showAllButton, indicator])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 10
        addSubview(stack)

        topLine.backgroundColor = .g_sectionTitleTop
        topLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topLine)

        bottomLine.backgroundColor = .g_sectionTitleBottom
        bottomLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomLine)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
                        
            topLine.heightAnchor.constraint(equalToConstant: pixelSize),
            topLine.topAnchor.constraint(equalTo: topAnchor),
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -44),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 44),
            
            bottomLine.heightAnchor.constraint(equalToConstant: pixelSize),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -44),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 44)
        ])
        
        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsLayout), name: .ModelDataUpdated, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func selected() {
        NotificationCenter.default.post(name: .SectionBackgroundTapped, object: BackgroundSelectionEvent(scene: self.window?.windowScene, frame: nil, name: self.label.text))
    }
    
    @objc private func showAllSelected() {
        NotificationCenter.default.post(name: .SectionShowAllTapped, object: BackgroundSelectionEvent(scene: self.window?.windowScene, frame: nil, name: self.label.text))
    }
    
    func configure(with toggle: ModelFilterContext.LabelToggle, firstSection: Bool, dataSource: UICollectionViewDiffableDataSource<SectionIdentifier, ItemIdentifier>, viewController: ViewController, menuOptions: [UIMenuElement]) {
        self.menuOptions = menuOptions
        self.dataSource = dataSource
        self.viewController = viewController
        self.toggle = toggle

        label.text = toggle.name

        switch toggle.displayMode {
        case .collapsed:
            label.isHighlighted = true
            indicator.isHighlighted = true
            indicator.tintColor = .label
            topLine.isHidden = firstSection
            bottomLine.isHidden = false
            showAllButton.setTitle(nil, for: .normal)

        case .scrolling:
            label.isHighlighted = false
            indicator.isHighlighted = false
            indicator.tintColor = .secondaryLabel
            topLine.isHidden = true
            bottomLine.isHidden = true
            showAllButton.setTitle("More", for: .normal)

        case .full:
            label.isHighlighted = false
            indicator.isHighlighted = false
            indicator.tintColor = .secondaryLabel
            topLine.isHidden = true
            bottomLine.isHidden = true
            showAllButton.setTitle("Less", for: .normal)
        }
    }
    
    override func layoutSubviews() {
        updateMoreButton()
        super.layoutSubviews()
    }
    
    private func updateMoreButton() {
        guard let toggle = self.toggle, let dataSource = self.dataSource, let viewController = self.viewController else { return }
        let count = dataSource.snapshot().numberOfItems(inSection: SectionIdentifier(label: toggle))
        showAllButton.isHidden = showAllButton.title(for: .normal) == nil || viewController.currentColumnCount >= count
    }
}

extension LabelSectionTitle: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            return UIMenu(title: "Sections", image: nil, identifier: nil, options: [], children: self.menuOptions)
        }
    }
}
