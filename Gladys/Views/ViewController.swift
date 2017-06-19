
import UIKit

final class ViewController: UIViewController, UICollectionViewDelegate, ArchivedItemCellDelegate,
UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, UICollectionViewDropDelegate, UICollectionViewDragDelegate {

	@IBOutlet weak var archivedItemCollectionView: UICollectionView!

	private let model = Model()

	/////////////////////////

	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		return [model.drops[indexPath.item].dragItem]
	}

	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		let newItem = model.drops[indexPath.item].dragItem
		if !session.items.contains(newItem) {
			return [newItem]
		} else {
			return []
		}
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return model.drops.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ArchivedItemCell", for: indexPath) as! ArchivedItemCell
		cell.setArchivedDropItem(model.drops[indexPath.item])
		cell.isEditing = isEditing
		cell.delegate = self
		return cell
	}

	private func handleDrop(collectionView: UICollectionView, coordinator: UICollectionViewDropCoordinator) {

		var changesMade = false

		for coordinatorItem in coordinator.items {
			let dragItem = coordinatorItem.dragItem

			if coordinator.session.localDragSession == nil {

				NSLog("insert drop")

				let item = ArchivedDropItem(provider: dragItem.itemProvider, delegate: nil)

				let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: model.drops.count, section: 0)

				collectionView.performBatchUpdates({
					self.model.drops.insert(item, at: destinationIndexPath.item)
					collectionView.insertItems(at: [destinationIndexPath])
				}, completion: nil)

				coordinator.drop(dragItem, toItemAt: destinationIndexPath)
				changesMade = true

			} else {

				NSLog("move drop")

				guard
					let destinationIndexPath = coordinator.destinationIndexPath,
					let existingItem = dragItem.localObject as? ArchivedDropItem,
					let previousIndex = coordinatorItem.sourceIndexPath else { return }

				NSLog("looks good")

				collectionView.performBatchUpdates({
					self.model.drops.remove(at: previousIndex.item)
					collectionView.deleteItems(at: [previousIndex])
					self.model.drops.insert(existingItem, at: destinationIndexPath.item)
					collectionView.insertItems(at: [destinationIndexPath])
				}, completion: nil)

				coordinator.drop(dragItem, toItemAt: destinationIndexPath)
				changesMade = true
			}
		}

		if changesMade {
			Model.save()
		}
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
			handleDrop(collectionView: collectionView, coordinator: coordinator)
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
		if collectionView.numberOfItems(inSection: 0) != model.drops.count {
			collectionView.endInteractiveMovement()
		}
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		let item = model.drops[indexPath.item]
		item.tryOpen()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		archivedItemCollectionView.dataSource = self
		archivedItemCollectionView.delegate = self
		archivedItemCollectionView.dropDelegate = self
		archivedItemCollectionView.dragDelegate = self
		archivedItemCollectionView.reorderingCadence = .immediate
		archivedItemCollectionView.backgroundView = UIImageView(image: #imageLiteral(resourceName: "paper").resizableImage(withCapInsets: .zero, resizingMode: .tile))

		let searchController = UISearchController(searchResultsController: nil)
		navigationItem.searchController = searchController
	}

	@IBAction func editSelected(_ sender: UIBarButtonItem) {
		isEditing = !isEditing
		sender.title = isEditing ? "Done" : "Edit"
		archivedItemCollectionView.reloadSections([0])
	}

	@IBAction func resetPressed(_ sender: UIBarButtonItem) {
		sender.isEnabled = false
		archivedItemCollectionView.performBatchUpdates({
			for item in self.model.drops {
				item.delete()
			}
			self.model.drops.removeAll()
			Model.save()
			self.archivedItemCollectionView.reloadSections(IndexSet(integer: 0))
		}, completion: { finished in
			sender.isEnabled = true
		})
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		let layout = (collectionViewLayout as! UICollectionViewFlowLayout)
		if view.bounds.size.width <= 320 {
			return CGSize(width: 300, height: 200)

		} else if view.bounds.size.width >= 1024 {
			let extras = layout.minimumInteritemSpacing * 3 + layout.sectionInset.left + layout.sectionInset.right
			let fourth = ((view.bounds.size.width - extras) / 4.0).rounded(.down)
			return CGSize(width: fourth, height: fourth)

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

	/////////////////////////////////

	func deleteRequested(for item: ArchivedDropItem) {
		if let i = model.drops.index(where: { $0 === item }) {
			archivedItemCollectionView.performBatchUpdates({
				self.model.drops.remove(at: i)
				self.archivedItemCollectionView.deleteItems(at: [IndexPath(item: i, section: 0)])
			}, completion: nil)
		}
		Model.save()
	}
}

