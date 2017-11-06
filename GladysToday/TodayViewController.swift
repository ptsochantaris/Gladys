//
//  TodayViewController.swift
//  GladysToday
//
//  Created by Paul Tsochantaris on 06/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import NotificationCenter

class TodayViewController: UIViewController, NCWidgetProviding, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

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
    
}
