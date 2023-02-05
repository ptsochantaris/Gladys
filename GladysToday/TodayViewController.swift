import GladysCommon
import NotificationCenter
import UIKit

final class TodayViewController: UIViewController, NCWidgetProviding, UICollectionViewDelegate,
    UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDragDelegate {
    @IBOutlet private var emptyLabel: UILabel!
    @IBOutlet private var itemsView: UICollectionView!
    @IBOutlet private var copiedLabel: UILabel!

    private var cellSize = CGSize.zero
    private var itemsPerRow = 1

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt _: IndexPath) -> CGSize {
        cellSize
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        let compact = extensionContext?.widgetActiveDisplayMode == .compact
        let numberOfRows = compact ? 1 : 3
        return min(itemsPerRow * numberOfRows, DropStore.visibleDrops.count)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TodayCell", for: indexPath) as! TodayCell
        cell.dropItem = DropStore.visibleDrops[indexPath.item]
        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let drop = DropStore.visibleDrops[indexPath.item]
        drop.copyToPasteboard()
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseOut, animations: {
            self.copiedLabel.alpha = 1
            self.itemsView.alpha = 0
        }, completion: { _ in
            UIView.animate(withDuration: 0.1, delay: 0.8, options: .curveEaseIn) {
                self.copiedLabel.alpha = 0
                self.itemsView.alpha = 1
            }
        })
    }

    func collectionView(_: UICollectionView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let drop = DropStore.visibleDrops[indexPath.item]
        return [drop.dragItem]
    }

    func collectionView(_: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point _: CGPoint) -> [UIDragItem] {
        let item = DropStore.visibleDrops[indexPath.item].dragItem
        if !session.items.contains(item) {
            return [item]
        } else {
            return []
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        extensionContext?.widgetLargestAvailableDisplayMode = .expanded
        itemsView.dragDelegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(openParentApp(_:)), name: .OpenParentApp, object: nil)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor(white: 0, alpha: 0.2)
        view.insertSubview(divider, at: 0)

        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
    }

    @objc private func openParentApp(_ notification: Notification) {
        if let url = notification.object as? URL {
            extensionContext?.open(url, completionHandler: nil)
        }
    }

    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize _: CGSize) {
        reloadData()

        let width = view.bounds.width
        if width < 320 {
            itemsPerRow = min(2, DropStore.visibleDrops.count)
        } else if width < 400 {
            itemsPerRow = min(3, DropStore.visibleDrops.count)
        } else {
            itemsPerRow = min(4, DropStore.visibleDrops.count)
        }

        let columnCount = CGFloat(itemsPerRow)

        guard columnCount > 0,
              let extensionContext,
              let layout = itemsView.collectionViewLayout as? UICollectionViewFlowLayout
        else {
            cellSize = .zero
            return
        }

        layout.minimumInteritemSpacing = itemsView.layoutMargins.left - 1
        layout.minimumLineSpacing = itemsView.layoutMargins.top - 1

        let margins = itemsView.layoutMargins

        var newSize = CGSize(width: width, height: extensionContext.widgetMaximumSize(for: .compact).height)
        newSize.width -= margins.left
        newSize.width -= margins.right
        newSize.width -= (columnCount - 1) * layout.minimumInteritemSpacing
        newSize.width = (newSize.width / columnCount).rounded(.down)

        newSize.height -= margins.top
        newSize.height -= margins.bottom
        if activeDisplayMode == .expanded {
            newSize.height -= 2
        }

        if newSize.width < 0 || newSize.height < 0 {
            cellSize = .zero
        } else {
            cellSize = newSize
        }

        updateUI()
    }

    private func updateUI() {
        copiedLabel.alpha = 0
        emptyLabel.isHidden = !DropStore.visibleDrops.isEmpty
        itemsView.reloadData()
        itemsView.layoutIfNeeded()
        preferredContentSize = itemsView.contentSize
    }

    private func reloadData() {
        Model.reloadDataIfNeeded(maximumItems: 12)
    }

    func widgetPerformUpdate(completionHandler: @escaping (NCUpdateResult) -> Void) {
        reloadData()
        updateUI()
        completionHandler(.newData)
    }

    private func dragParameters(for indexPath: IndexPath) -> UIDragPreviewParameters? {
        if let cell = itemsView.cellForItem(at: indexPath) as? TodayCell, let b = cell.backgroundView {
            let corner = b.layer.cornerRadius
            let path = UIBezierPath(roundedRect: b.frame, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: corner, height: corner))
            let params = UIDragPreviewParameters()
            params.visiblePath = path
            return params
        } else {
            return nil
        }
    }

    func collectionView(_: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        dragParameters(for: indexPath)
    }
}
