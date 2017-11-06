//
//  TodayViewController.swift
//  GladysToday
//
//  Created by Paul Tsochantaris on 06/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import NotificationCenter

class TodayViewController: UIViewController, NCWidgetProviding, UICollectionViewDelegate,
UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDragDelegate {

	@IBOutlet weak var emptyLabel: UILabel!
	@IBOutlet weak var itemsView: UICollectionView!
	@IBOutlet weak var copiedLabel: UILabel!

	private var itemCount: Int {
		let s = view.bounds.size
		let count: Int
		if s.width < 320 {
			count = 2
		} else if s.width < 400 {
			count = 3
		} else {
			count = 4
		}
		return min(count, Model.drops.count)
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		let count = CGFloat(itemCount)
		var s = view.bounds.size
		s.height -= 20
		s.width = ((s.width - ((count+1) * 10)) / count).rounded(.down)
		return s
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return itemCount
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TodayCell", for: indexPath) as! TodayCell
		cell.dropItem = Model.drops[indexPath.row]
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		Model.reloadDataIfNeeded()
		let drop = Model.drops[indexPath.row]
		drop.copyToPasteboard()
		UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
			self.copiedLabel.alpha = 1
			self.itemsView.alpha = 0
		}) { finished in
			UIView.animate(withDuration: 0.2, delay: 0.8, options: .curveEaseIn, animations: {
				self.copiedLabel.alpha = 0
				self.itemsView.alpha = 1
			}) { finished in
			}
		}
	}

	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		Model.reloadDataIfNeeded()
		let drop = Model.drops[indexPath.row]
		return [drop.dragItem]
	}

	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		Model.reloadDataIfNeeded()
		let item = Model.drops[indexPath.row].dragItem
		if !session.items.contains(item) {
			return [item]
		} else {
			return []
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		itemsView.dragDelegate = self
	}

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
		Model.reset()
    }

	private func updateUI() {
		Model.reloadDataIfNeeded()
		copiedLabel.alpha = 0
		emptyLabel.isHidden = Model.drops.count > 0
		itemsView.reloadData()
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
			params.backgroundColor = .clear
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
