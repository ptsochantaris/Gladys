//
//  TodayViewController.swift
//  GladysToday
//
//  Created by Paul Tsochantaris on 06/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import NotificationCenter

final class TodayViewController: UIViewController, NCWidgetProviding, UICollectionViewDelegate,
UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDragDelegate {

	@IBOutlet private weak var emptyLabel: UILabel!
	@IBOutlet private weak var itemsView: UICollectionView!
	@IBOutlet private weak var copiedLabel: UILabel!
            
    private var cellSize = CGSize.zero
    private var itemsPerRow = 1
    
	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		return cellSize
	}
        
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let compact = extensionContext?.widgetActiveDisplayMode == .compact
        let numberOfRows: Int
        if #available(iOS 14.0, *) {
            numberOfRows = compact ? 1 : 3
        } else {
            numberOfRows = compact ? 1 : 4
        }
		return min(itemsPerRow * numberOfRows, Model.visibleDrops.count)
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TodayCell", for: indexPath) as! TodayCell
		cell.dropItem = Model.visibleDrops[indexPath.item]
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		let drop = Model.visibleDrops[indexPath.item]
		drop.copyToPasteboard()
		UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseOut, animations: {
			self.copiedLabel.alpha = 1
			self.itemsView.alpha = 0
        }, completion: { _ in
            UIView.animate(withDuration: 0.1, delay: 0.8, options: .curveEaseIn, animations: {
				self.copiedLabel.alpha = 0
				self.itemsView.alpha = 1
			}, completion: nil)
		})
	}

	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		let drop = Model.visibleDrops[indexPath.item]
		return [drop.dragItem]
	}

	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		let item = Model.visibleDrops[indexPath.item].dragItem
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

	func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        reloadData()

        let width = view.bounds.width
        if width < 320 {
            itemsPerRow = min(2, Model.visibleDrops.count)
        } else if width < 400 {
            itemsPerRow = min(3, Model.visibleDrops.count)
        } else {
            itemsPerRow = min(4, Model.visibleDrops.count)
        }
        
        let columnCount = CGFloat(itemsPerRow)
        
        guard columnCount > 0,
            let extensionContext = extensionContext,
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
        newSize.width /= columnCount
        
        newSize.height -= margins.top
        newSize.height -= margins.bottom
        if #available(iOS 14.0, *), activeDisplayMode == .expanded {
            newSize.height -= 2
        }

        cellSize = newSize
        
		updateUI()
	}

	private func updateUI() {
		copiedLabel.alpha = 0
		emptyLabel.isHidden = !Model.visibleDrops.isEmpty
        itemsView.reloadData()
        itemsView.layoutIfNeeded()
        preferredContentSize = itemsView.contentSize
	}
    
    private func reloadData() {
        let max: Int
        if #available(iOS 14.0, *) {
            max = 12
        } else {
            max = 16
        }
        Model.reloadDataIfNeeded(maximumItems: max)
    }

    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        reloadData()
		updateUI()
        completionHandler(NCUpdateResult.newData)
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

	func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
		return dragParameters(for: indexPath)
	}
}
