import UIKit
import GladysCommon

final class GridLayout: UICollectionViewLayout {
    var cellSide: CGFloat = 36

    override var collectionViewContentSize: CGSize {
        guard let c = collectionView else { return .zero }
        let bounds = c.bounds
        let itemsPerRow = (bounds.width / cellSide).rounded(.down)
        let count = c.numberOfItems(inSection: 0)
        let rows = (CGFloat(count) / itemsPerRow).rounded(.up)
        return CGSize(width: itemsPerRow * cellSide, height: rows * cellSide)
    }

    private var itemsPerRow = 10
    private var width: CGFloat = 100
    private var offset: CGFloat = 0
    override func invalidateLayout() {
        super.invalidateLayout()
        if let c = collectionView {
            width = c.bounds.width
            itemsPerRow = width > 640 ? 16 : width > 480 ? 12 : 8
            cellSide = (width / CGFloat(itemsPerRow)).rounded(.down)
            offset = ((width - (CGFloat(itemsPerRow) * cellSide)) * 0.5).rounded(.down)
        }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        width != newBounds.size.width
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let index = indexPath.row
        let row = CGFloat(index / itemsPerRow)
        let column = CGFloat(index % itemsPerRow)

        let attrs = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attrs.frame = CGRect(x: offset + column * cellSide, y: row * cellSide, width: cellSide, height: cellSide)
        return attrs
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let y = max(0, rect.origin.y)
        let minIndex = Int((y / cellSide).rounded(.down)) * itemsPerRow
        let maxIndex = Int(((y + rect.size.height) / cellSide).rounded(.up)) * itemsPerRow
        let count = collectionView?.numberOfItems(inSection: 0) ?? 0

        let ips = LinkedList<UICollectionViewLayoutAttributes>()
        for f in min(count, minIndex) ..< min(count, maxIndex) {
            if let a = layoutAttributesForItem(at: IndexPath(item: f, section: 0)) {
                ips.append(a)
            }
        }
        return Array(ips)
    }
}
