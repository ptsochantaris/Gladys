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
        let originalColor = contentView.backgroundColor
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.contentView.backgroundColor = UIColor.g_colorTint
        } completion: { _ in
            UIView.animate(withDuration: 0.6, delay: 0, options: .curveEaseIn) {
                self.contentView.backgroundColor = originalColor
            }
        }
    }

    open func setup() {
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        itemViewController.view.backgroundColor = .clear
        itemViewController.view.isOpaque = false
        layer.shouldRasterize = true
        setNeedsLayout()
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
        return UITargetedPreview(view: itemViewController.view, parameters: params)
    }

    private var itemViewController = UIHostingController(rootView: ItemView())
    public weak var owningViewController: UIViewController?
    public weak var archivedDropItem: ArchivedItem? {
        didSet {
            lastLayout = .zero
            setNeedsLayout()
        }
    }

    public var lastLayout = CGSize.zero
    public var style = ArchivedItemWrapper.Style.square

    override open func layoutSubviews() {
        if lastLayout != bounds.size {
            lastLayout = bounds.size

            itemViewController.rootView.setItem(archivedDropItem, for: bounds.size, style: style)

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

    public var lowMemoryMode = false {
        didSet {
            if lowMemoryMode != oldValue {
                lastLayout = .zero
                setNeedsLayout()
            }
        }
    }

    override public var isSelected: Bool {
        get { archivedDropItem?.flags.contains(.selected) ?? false }
        set {
            guard let archivedDropItem else { return }
            if newValue {
                archivedDropItem.flags.insert(.selected)
            } else {
                archivedDropItem.flags.remove(.selected)
            }
            archivedDropItem.objectWillChange.send()
        }
    }

    public var isEditing: Bool {
        get { archivedDropItem?.flags.contains(.editing) ?? false }
        set {
            guard let archivedDropItem else { return }
            if newValue {
                archivedDropItem.flags.insert(.editing)
            } else {
                archivedDropItem.flags.remove(.editing)
            }
            archivedDropItem.objectWillChange.send()
        }
    }
}
