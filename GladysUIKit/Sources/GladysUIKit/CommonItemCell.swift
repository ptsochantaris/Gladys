import GladysCommon
import GladysUI
import SwiftUI
import UIKit

open class CommonItemCell: UICollectionViewCell {
    public var dragParameters: UIDragPreviewParameters {
        let params = UIDragPreviewParameters()
        params.backgroundColor = .clear
        let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: cellCornerRadius, height: cellCornerRadius))
        params.visiblePath = path
        params.shadowPath = path
        return params
    }

    public func flash() {
        guard let v = itemViewController.view else {
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0.1, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
            v.transform = .init(scaleX: 0.9, y: 0.9)
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.1, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
                v.transform = .identity
            }
        }
    }

    private func invalidateView() {
        lastLayout = .zero
        setNeedsLayout()
    }

    open func setup() {
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        itemViewController.view.backgroundColor = .clear
        itemViewController.view.isOpaque = false
        layer.shouldRasterize = true
        setNeedsLayout()

        registerForTraitChanges([UITraitActiveAppearance.self]) { [weak self] (_: UITraitEnvironment, _: UITraitCollection) in
            guard let archivedDropItem = self?.archivedDropItem else { return }
            archivedDropItem.postModified()
        }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    public var targetedPreviewItem: UITargetedPreview {
        let params = UIDragPreviewParameters()
        params.visiblePath = UIBezierPath(roundedRect: bounds, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: cellCornerRadius, height: cellCornerRadius))
        return UITargetedPreview(view: self, parameters: params)
    }

    private let myWrapper = ArchivedItemWrapper()
    private lazy var itemViewController = UIHostingController(rootView: ItemView(wrapper: myWrapper))
    public weak var owningViewController: UIViewController?
    public weak var archivedDropItem: ArchivedItem? {
        didSet {
            invalidateView()
        }
    }

    public func didEndDisplaying() {
        myWrapper.clear()
    }

    private var lastLayout = CGSize.zero
    public var style = ArchivedItemWrapper.Style.square

    public var shade: Bool {
        get {
            myWrapper.shade
        }
        set {
            withAnimation {
                myWrapper.shade = newValue
            }
        }
    }

    override open func layoutSubviews() {
        let currentSize = bounds.size
        if lastLayout != currentSize {
            lastLayout = currentSize

            if lowMemoryMode {
                myWrapper.clear()
            } else {
                myWrapper.configure(with: archivedDropItem, size: bounds.size, style: style)
            }

            if itemViewController.parent == nil, let owningViewController {
                owningViewController.addChildController(itemViewController, to: contentView)
            }
        }

        #if os(visionOS)
            layer.rasterizationScale = 2
        #else
            layer.rasterizationScale = window?.screen.scale ?? UIScreen.main.scale
        #endif

        super.layoutSubviews()

        focusEffect = UIFocusHaloEffect(roundedRect: bounds.insetBy(dx: 2, dy: 2), cornerRadius: cellCornerRadius, curve: .continuous)
    }

    override open var accessibilityValue: String? {
        get {
            myWrapper.accessibilityText
        }
        set {}
    }

    override open var isAccessibilityElement: Bool {
        get {
            true
        }
        set {}
    }

    public var lowMemoryMode = false {
        didSet {
            if lowMemoryMode != oldValue {
                invalidateView()
            }
        }
    }

    override public var isSelected: Bool {
        get { archivedDropItem?.flags.contains(.selected) ?? false }
        set {
            guard let archivedDropItem, newValue != isSelected else { return }
            if newValue {
                archivedDropItem.flags.insert(.selected)
            } else {
                archivedDropItem.flags.remove(.selected)
            }
            archivedDropItem.postModified()
        }
    }

    public var isEditing: Bool {
        get { archivedDropItem?.flags.contains(.editing) ?? false }
        set {
            guard let archivedDropItem, newValue != isEditing else { return }
            if newValue {
                archivedDropItem.flags.insert(.editing)
            } else {
                archivedDropItem.flags.remove(.editing)
            }
            archivedDropItem.postModified()
        }
    }
}
