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
    private var mode = ModelFilterContext.DisplayMode.collapsed
    private var sectionCount = 0
    private var layoutForParentCount = 0
    private var toggle: ModelFilterContext.LabelToggle?
    private weak var viewController: ViewController?

    private static let titleStyle = UIFont.TextStyle.subheadline

    private func setup() {
        
        tintColor = .secondaryLabel
        isUserInteractionEnabled = true
        addInteraction(UIDragInteraction(delegate: self))
        addInteraction(UIContextMenuInteraction(delegate: self))
        
        layer.cornerRadius = 15

        let labelFont = UIFont.preferredFont(forTextStyle: LabelSectionTitle.titleStyle)
        
        label.font = labelFont
        label.isUserInteractionEnabled = true
        label.textColor = .secondaryLabel
        label.highlightedTextColor = .label
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        indicator.contentMode = .center
        let textStyle = UIImage.SymbolConfiguration(textStyle: LabelSectionTitle.titleStyle)
        indicator.highlightedImage = UIImage(systemName: "chevron.right")?.applyingSymbolConfiguration(textStyle)
        indicator.image = UIImage(systemName: "chevron.down")?.applyingSymbolConfiguration(textStyle)
        indicator.setContentHuggingPriority(.required, for: .horizontal)
        indicator.setContentCompressionResistancePriority(.required, for: .horizontal)
        indicator.isUserInteractionEnabled = true
        
        showAllButton.titleLabel?.font = labelFont
        showAllButton.addTarget(self, action: #selector(showAllSelected), for: .touchUpInside)
        showAllButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        showAllButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        showAllButton.setTitleColor(UIColor.g_colorTint, for: .normal)
        
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
    
    func configure(with toggle: ModelFilterContext.LabelToggle, firstSection: Bool, count: Int, viewController: ViewController, menuOptions: [UIMenuElement]) {
        self.viewController = viewController
        self.menuOptions = menuOptions
        self.sectionCount = count
        self.toggle = toggle
        
        mode = toggle.displayMode
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
        
        updateMoreButton()
    }
    
    override func layoutSubviews() {
        if let viewController = viewController, layoutForParentCount != viewController.currentColumnCount {
            updateMoreButton()
        }
        super.layoutSubviews()
    }
    
    private func updateMoreButton() {
        guard let viewController = viewController else {
            return
        }
        let current = viewController.currentColumnCount
        showAllButton.isHidden = mode == .collapsed || sectionCount <= current
        layoutForParentCount = current
    }
    
    private var previewRect: CGRect {
        return CGRect(x: 0, y: 0, width: 280, height: LabelSectionTitle.height * 2)
    }
    
    private func createLabelView() -> UIView {
        let labelView = UILabel(frame: .zero)
        labelView.text = self.toggle?.name
        labelView.font = UIFont.preferredFont(forTextStyle: .headline)
        labelView.textColor = UIColor.g_colorTint
        labelView.textAlignment = .center
        labelView.setContentHuggingPriority(.required, for: .vertical)
        
        let n = NumberFormatter()
        n.numberStyle = .decimal
        let number = n.string(for: layoutForParentCount) ?? ""

        let countView = UILabel(frame: .zero)
        countView.text = "\(number) items"
        countView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        countView.textColor = UIColor.secondaryLabel
        countView.textAlignment = .center
        countView.setContentHuggingPriority(.required, for: .vertical)

        let stack = UIStackView(arrangedSubviews: [labelView, countView])
        stack.axis = .vertical
        stack.spacing = 2

        let holder = UIView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: holder.trailingAnchor)
        ])

        holder.frame = previewRect
        return holder
    }
    
    private func dragParams() -> UIDragPreviewParameters {
        let params = UIDragPreviewParameters()
        params.visiblePath = UIBezierPath(roundedRect: previewRect, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 15, height: 15))
        return params
    }
}

extension LabelSectionTitle: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil) {
            let vc = UIViewController()
            let labelView = self.createLabelView()
            vc.preferredContentSize = labelView.frame.size
            vc.view.addSubview(labelView)
            return vc
        } actionProvider: { _ in
            return UIMenu(title: "All Sections", image: nil, identifier: nil, options: [], children: self.menuOptions)
        }
    }
}

extension LabelSectionTitle: UIDragInteractionDelegate {
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        if let toggle = toggle, let label = toggle.name.labelDragItem {
            label.previewProvider = {
                return UIDragPreview(view: self.createLabelView(), parameters: self.dragParams())
            }
            return [label]
        } else {
            return []
        }
    }
}
