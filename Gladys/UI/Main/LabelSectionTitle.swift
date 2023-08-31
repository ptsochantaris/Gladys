import GladysCommon
import GladysUI
import UIKit
import Minions

final class PassthroughStackView: UIStackView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for s in arrangedSubviews where s.isUserInteractionEnabled {
            let converted = convert(point, to: s)
            if let view = s.hitTest(converted, with: event) {
                return view
            }
        }
        return nil
    }
}

final class ScrollFadeView: UICollectionReusableView {
    private weak var viewController: ViewController?
    private var toggle: Filter.Toggle?

    private var sectionCount: Int {
        guard let viewController, let toggle else {
            return 0
        }
        return viewController.filter.countItems(for: toggle)
    }

    func configure(with toggle: Filter.Toggle, viewController: ViewController) {
        self.toggle = toggle
        self.viewController = viewController
        updateColor()
    }

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        #notifications(for: .ModelDataUpdated) { _ in
            updateColor()
            return true
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColor()
    }

    private func updateColor() {
        let g = layer as! CAGradientLayer
        if let count = viewController?.currentColumnCount, sectionCount > count {
            g.startPoint = CGPoint(x: 0, y: 0)
            g.endPoint = CGPoint(x: 1, y: 0)
            let two = UIColor.g_expandedSection
            let one = two.withAlphaComponent(0)
            g.colors = [one.cgColor, two.cgColor]
            g.isHidden = false
        } else {
            g.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

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
    private var mode = Filter.DisplayMode.collapsed
    private var layoutForColumnCount = 0
    private var toggle: Filter.Toggle?
    private weak var viewController: ViewController?

    private static let titleStyle = UIFont.TextStyle.subheadline

    private func setup() {
        tintColor = .secondaryLabel
        isUserInteractionEnabled = true
        addInteraction(UIDragInteraction(delegate: self))
        addInteraction(UIContextMenuInteraction(delegate: self))
        
        addInteraction(UISpringLoadedInteraction { [weak self] _, context in
            guard let self else { return }
            if context.state == .activated, mode == .collapsed {
                sendNotification(name: .SectionHeaderTapped, object: BackgroundSelectionEvent(scene: window?.windowScene, frame: nil, name: label.text))
            }
        })
        
        layer.cornerRadius = 15
        
        let selectionButton = UIButton(primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            sendNotification(name: .SectionHeaderTapped, object: BackgroundSelectionEvent(scene: window?.windowScene, frame: nil, name: label.text))
        })
        selectionButton.translatesAutoresizingMaskIntoConstraints = false
        
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        indicator.contentMode = .center
        let textStyle = UIImage.SymbolConfiguration(textStyle: LabelSectionTitle.titleStyle)
        indicator.highlightedImage = UIImage(systemName: "chevron.right")?.applyingSymbolConfiguration(textStyle)
        indicator.image = UIImage(systemName: "chevron.down")?.applyingSymbolConfiguration(textStyle)
        indicator.setContentHuggingPriority(.required, for: .horizontal)
        indicator.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        showAllButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: LabelSectionTitle.titleStyle)
        showAllButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            sendNotification(name: .SectionShowAllTapped, object: BackgroundSelectionEvent(scene: window?.windowScene, frame: nil, name: label.text))
        }, for: .primaryActionTriggered)
        showAllButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        showAllButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        showAllButton.setTitleColor(UIColor.g_colorTint, for: .normal)
        
        let stack = PassthroughStackView(arrangedSubviews: [label, showAllButton, indicator])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 10
        
        topLine.isUserInteractionEnabled = false
        topLine.backgroundColor = .g_sectionTitleTop
        topLine.translatesAutoresizingMaskIntoConstraints = false
        
        bottomLine.isUserInteractionEnabled = false
        bottomLine.backgroundColor = .g_sectionTitleBottom
        bottomLine.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(selectionButton)
        addSubview(topLine)
        addSubview(bottomLine)
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            selectionButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectionButton.topAnchor.constraint(equalTo: topAnchor),
            selectionButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: -2),
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
        
        #notifications(for: .ModelDataUpdated) { _ in
            setNeedsLayout()
            return true
        }
    }

    func reset() {
        layoutForColumnCount = 0
        setNeedsLayout()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configure(with toggle: Filter.Toggle, firstSection: Bool, viewController: ViewController, menuOptions: [UIMenuElement]) {
        self.viewController = viewController
        self.menuOptions = menuOptions
        self.toggle = toggle

        mode = toggle.currentDisplayMode
        label.text = toggle.function.displayText
        let labelFont = UIFont.preferredFont(forTextStyle: LabelSectionTitle.titleStyle)

        switch toggle.currentDisplayMode {
        case .collapsed:
            if case .userLabel = toggle.function {
                label.font = labelFont
            } else {
                label.font = UIFont.systemFont(ofSize: labelFont.pointSize, weight: .medium)
            }
            label.textColor = .label
            indicator.isHighlighted = true
            indicator.tintColor = .label
            topLine.isHidden = firstSection
            bottomLine.isHidden = false
            showAllButton.setTitle(nil, for: .normal)

        case .scrolling:
            label.font = labelFont
            label.textColor = .secondaryLabel
            indicator.isHighlighted = false
            indicator.tintColor = .secondaryLabel
            topLine.isHidden = true
            bottomLine.isHidden = true
            showAllButton.setTitle("More", for: .normal)

        case .full:
            label.font = labelFont
            label.textColor = .secondaryLabel
            indicator.isHighlighted = false
            indicator.tintColor = .secondaryLabel
            topLine.isHidden = true
            bottomLine.isHidden = true
            showAllButton.setTitle("Less", for: .normal)
        }

        updateMoreButton()
    }

    override func layoutSubviews() {
        if let viewController, layoutForColumnCount != viewController.currentColumnCount {
            updateMoreButton()
        }
        super.layoutSubviews()
    }

    private func updateMoreButton() {
        guard let viewController else {
            return
        }
        let current = viewController.currentColumnCount
        showAllButton.isHidden = mode == .collapsed || sectionCount <= current
        layoutForColumnCount = current
    }

    private var sectionCount: Int {
        guard let viewController, let toggle else {
            return 0
        }
        return viewController.filter.countItems(for: toggle)
    }

    private var previewRect: CGRect {
        CGRect(x: 0, y: 0, width: 280, height: LabelSectionTitle.height * 2)
    }

    private func createLabelView() -> UIView {
        let labelView = UILabel(frame: .zero)
        labelView.text = toggle?.function.displayText
        labelView.font = UIFont.preferredFont(forTextStyle: .headline)
        labelView.textColor = UIColor.g_colorTint
        labelView.textAlignment = .center
        labelView.setContentHuggingPriority(.required, for: .vertical)

        let n = NumberFormatter()
        n.numberStyle = .decimal
        let number = n.string(for: sectionCount) ?? ""

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
    func contextMenuInteraction(_: UIContextMenuInteraction, configurationForMenuAtLocation _: CGPoint) -> UIContextMenuConfiguration? {
        var myOptions = menuOptions
        if UIApplication.shared.supportsMultipleScenes, let scene = window?.windowScene {
            let windowOption = UIAction(title: "Open in Window", image: UIImage(systemName: "uiwindow.split.2x1")) { [weak self] _ in
                self?.toggle?.function.openInWindow(from: scene)
            }
            myOptions.append(windowOption)
        }

        return UIContextMenuConfiguration(identifier: nil) {
            let vc = UIViewController()
            let labelView = self.createLabelView()
            vc.preferredContentSize = labelView.frame.size
            vc.view.addSubview(labelView)
            return vc
        } actionProvider: { _ in
            UIMenu(title: "All Sections", image: nil, identifier: nil, options: [], children: myOptions)
        }
    }
}

extension LabelSectionTitle: UIDragInteractionDelegate {
    func dragInteraction(_: UIDragInteraction, itemsForBeginning _: UIDragSession) -> [UIDragItem] {
        if let toggle, let label = toggle.function.dragItem {
            label.previewProvider = {
                UIDragPreview(view: self.createLabelView(), parameters: self.dragParams())
            }
            return [label]
        } else {
            return []
        }
    }
}
