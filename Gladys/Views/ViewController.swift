//
//  ViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 16/06/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class ViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, UICollectionViewDropDelegate, UICollectionViewDragDelegate {

	@IBOutlet weak var archivedItemCollectionView: UICollectionView!

	private var archivedDrops = [ArchivedDrop]()

	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		return archivedDrops[indexPath.item].dragItems
	}

	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		let newItems = archivedDrops[indexPath.item].dragItems
		let onlyNewItems = newItems.filter { !session.items.contains($0) }
		return onlyNewItems
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return archivedDrops.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ArchivedItemCell", for: indexPath) as! ArchivedItemCell
		cell.setArchivedDrop(archivedDrops[indexPath.item])
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

		if let _ = coordinator.session.localDragSession {

			NSLog("local drop")

			if let destinationIndexPath = coordinator.destinationIndexPath,
				let firstDragItem = coordinator.items.first,
				let existingItem = firstDragItem.dragItem.localObject as? ArchivedDrop,
				let previousIndex = firstDragItem.sourceIndexPath {

				collectionView.performBatchUpdates({
					self.archivedDrops.remove(at: previousIndex.item)
					self.archivedDrops.insert(existingItem, at: destinationIndexPath.item)
					collectionView.moveItem(at: previousIndex, to: destinationIndexPath)
				}, completion: { finished in

				})

				coordinator.drop(firstDragItem.dragItem, toItemAt: destinationIndexPath)
			}

		} else {

			NSLog("insert drop")

			let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: archivedDrops.count, section: 0)
			if let firstDragItem = coordinator.items.first?.dragItem {

				let item = ArchivedDrop(session: coordinator.session)

				collectionView.performBatchUpdates({
					self.archivedDrops.insert(item, at: destinationIndexPath.item)
					collectionView.insertItems(at: [destinationIndexPath])
				}, completion: { finished in

				})

				coordinator.drop(firstDragItem, toItemAt: destinationIndexPath)
			}
		}
	}

	func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
		return true
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		if session.localDragSession == nil {
			return UICollectionViewDropProposal(dropOperation: .copy, intent: .insertAtDestinationIndexPath)
		} else {
			return UICollectionViewDropProposal(dropOperation: .move, intent: .insertAtDestinationIndexPath)
		}
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
		// TODO: possibe bug
		if collectionView.numberOfItems(inSection: 0) != archivedDrops.count {
			collectionView.endInteractiveMovement()
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		archivedItemCollectionView.dataSource = self
		archivedItemCollectionView.delegate = self
		archivedItemCollectionView.dropDelegate = self
		archivedItemCollectionView.dragDelegate = self
		archivedItemCollectionView.reorderingCadence = .immediate
	}

	@IBAction func editSelected(_ sender: UIBarButtonItem) {
		//archivedItemCollectionView.edit
	}

	@IBAction func resetPressed(_ sender: UIBarButtonItem) {
		sender.isEnabled = false
		archivedItemCollectionView.performBatchUpdates({
			self.archivedDrops.removeAll()
			self.archivedItemCollectionView.reloadSections(IndexSet(integer: 0))
		}, completion: { finished in
			sender.isEnabled = true
		})
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		let layout = (collectionViewLayout as! UICollectionViewFlowLayout)
		if view.bounds.size.width <= 320 {
			return CGSize(width: 300, height: 150)
		} else if view.bounds.size.width >= 694 {
			let extras = layout.minimumInteritemSpacing * 2 + layout.sectionInset.left + layout.sectionInset.right
			let third = ((view.bounds.size.width - extras) / 3.0).rounded(.down)
			return CGSize(width: third, height: third)
		} else {
			let extras = layout.minimumInteritemSpacing + layout.sectionInset.left + layout.sectionInset.right
			let third = ((view.bounds.size.width - extras) / 2.0).rounded(.down)
			return CGSize(width: third, height: third)
		}
	}

	private var lastSize: CGSize?
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		let boundsSize = view.bounds.size
		if let lastSize = lastSize {
			if lastSize == boundsSize { return }
			archivedItemCollectionView.performBatchUpdates({
			}, completion: nil)
		}
		lastSize = view.bounds.size
	}
}

