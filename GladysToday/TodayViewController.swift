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

	private var itemsPerRow: Int {
		let c = Model.visibleDrops.count
		let s = itemsView.bounds.size
		if s.width < 320 {
			return min(2, c)
		} else if s.width < 400 {
			return min(3, c)
		} else {
			return min(4, c)
		}
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		let compactHeight = extensionContext?.widgetMaximumSize(for: .compact).height ?? 110
		let count = CGFloat(itemsPerRow)
		var s = view.bounds.size
		s.height = compactHeight - 20
		s.width = ((s.width - ((count+1) * 10)) / count).rounded(.down)
		return s
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		let count = itemsPerRow * (extensionContext?.widgetActiveDisplayMode == .compact ? 1 : 4)
		return min(count, Model.visibleDrops.count)
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TodayCell", for: indexPath) as! TodayCell
		cell.dropItem = Model.visibleDrops[indexPath.item]
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		let drop = Model.visibleDrops[indexPath.item]
		drop.copyToPasteboard()
		UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut, animations: {
			self.copiedLabel.alpha = 1
			self.itemsView.alpha = 0
		}) { finished in
			UIView.animate(withDuration: 0.15, delay: 1, options: .curveEaseIn, animations: {
				self.copiedLabel.alpha = 0
				self.itemsView.alpha = 1
			}) { finished in
			}
		}
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
	}

	@objc private func openParentApp(_ notification: Notification) {
		if let url = notification.object as? URL {
			extensionContext?.open(url, completionHandler: nil)
		}
	}

	func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
		updateUI()
	}

    override func didReceiveMemoryWarning() {
		clearCaches()
        super.didReceiveMemoryWarning()
    }

	private func updateUI() {
		Model.reloadDataIfNeeded(maximumItems: 16)
		copiedLabel.alpha = 0
		emptyLabel.isHidden = Model.visibleDrops.count > 0
		itemsView.reloadData()
		itemsView.layoutIfNeeded()
		preferredContentSize = itemsView.contentSize
	}

    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
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
