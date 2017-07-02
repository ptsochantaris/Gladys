
import UIKit
import CoreSpotlight

final class ViewController: UIViewController, UICollectionViewDelegate,
	ArchivedItemCellDelegate, LoadCompletionDelegate,
	UISearchControllerDelegate, UISearchResultsUpdating,
	UICollectionViewDelegateFlowLayout, UICollectionViewDataSource,
	UICollectionViewDropDelegate, UICollectionViewDragDelegate {

	@IBOutlet weak var archivedItemCollectionView: UICollectionView!
	@IBOutlet weak var countLabel: UIBarButtonItem!
	@IBOutlet weak var totalSizeLabel: UIBarButtonItem!

	private let model = Model()

	static var shared: ViewController!

	/////////////////////////

	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		return [model.filteredDrops[indexPath.item].dragItem]
	}

	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		let newItem = model.filteredDrops[indexPath.item].dragItem
		if !session.items.contains(newItem) {
			return [newItem]
		} else {
			return []
		}
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return model.filteredDrops.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ArchivedItemCell", for: indexPath) as! ArchivedItemCell
		cell.archivedDropItem = model.filteredDrops[indexPath.item]
		cell.isEditing = isEditing
		cell.delegate = self
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

		var needSave = false

		coordinator.session.progressIndicatorStyle = .none

		for coordinatorItem in coordinator.items {
			let dragItem = coordinatorItem.dragItem

			if let existingItem = dragItem.localObject as? ArchivedDropItem {

				guard
					let destinationIndexPath = coordinator.destinationIndexPath,
					let previousIndex = coordinatorItem.sourceIndexPath else { return }

				collectionView.performBatchUpdates({
					self.model.drops.remove(at: previousIndex.item)
					self.model.drops.insert(existingItem, at: destinationIndexPath.item)
					collectionView.deleteItems(at: [previousIndex])
					collectionView.insertItems(at: [destinationIndexPath])
				})

				coordinator.drop(dragItem, toItemAt: destinationIndexPath)
				needSave = true

			} else {

				let item = ArchivedDropItem(provider: dragItem.itemProvider, delegate: self)
				let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: model.drops.count, section: 0)

				collectionView.performBatchUpdates({
					self.model.drops.insert(item, at: destinationIndexPath.item)
					collectionView.insertItems(at: [destinationIndexPath])
				})

				coordinator.drop(dragItem, toItemAt: destinationIndexPath)
				// save gets handled by the item loading correctly
			}
		}

		if needSave{
			model.save()
		}
	}

	func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
		return true
	}

	private func someWillBeInserts(in session: UIDropSession) -> Bool {
		for i in session.items {
			if !(i.localObject is ArchivedDropItem) {
				return true
			}
		}
		return false
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidEnter session: UIDropSession) {
		if someWillBeInserts(in: session) {
			resetSearch()
		}
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		if someWillBeInserts(in: session) {
			return UICollectionViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
		} else {
			if model.isFiltering {
				return UICollectionViewDropProposal(operation: .forbidden)
			} else {
				return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
			}
		}
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		let n = storyboard?.instantiateViewController(withIdentifier: "DetailController") as! UINavigationController
		let d = n.topViewController as! DetailController
		d.item = model.filteredDrops[indexPath.item]
		n.modalPresentationStyle = .popover
		navigationController?.visibleViewController?.present(n, animated: true)
		if let p = n.popoverPresentationController, let cell = collectionView.cellForItem(at: indexPath) {
			p.permittedArrowDirections = [.any]
			p.sourceView = cell
			p.sourceRect = cell.bounds.insetBy(dx: 5, dy: 0)
			let c = UIColor(patternImage: (archivedItemCollectionView.backgroundView as! UIImageView).image!)
			if traitCollection.horizontalSizeClass == .regular {
				p.backgroundColor = c
			} else {
				n.view.backgroundColor = c
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		ViewController.shared = self

		archivedItemCollectionView.dropDelegate = self
		archivedItemCollectionView.dragDelegate = self
		archivedItemCollectionView.reorderingCadence = .immediate
		archivedItemCollectionView.dataSource = self
		archivedItemCollectionView.delegate = self
		archivedItemCollectionView.backgroundView = UIImageView(image: #imageLiteral(resourceName: "paper").resizableImage(withCapInsets: .zero, resizingMode: .tile))

		CSSearchableIndex.default().indexDelegate = model

		let searchController = UISearchController(searchResultsController: nil)
		searchController.dimsBackgroundDuringPresentation = false
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.delegate = self
		searchController.searchResultsUpdater = self
		searchController.searchBar.tintColor = view.tintColor
		navigationItem.searchController = searchController

		searchTimer = PopTimer(timeInterval: 0.3) { [weak self, weak searchController] in
			self?.model.filter = searchController?.searchBar.text
		}

		navigationController?.setToolbarHidden(true, animated: false)

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(searchUpdated), name: .SearchResultsUpdated, object: nil)
		n.addObserver(self, selector: #selector(updateTotals), name: .SaveComplete, object: nil)
		n.addObserver(self, selector: #selector(deleteDetected(_:)), name: .DeleteSelected, object: nil)
		n.addObserver(self, selector: #selector(externalDataUpdate), name: .ExternalDataUpdated, object: nil)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@objc private func externalDataUpdate() {
		archivedItemCollectionView.reloadData()
		updateTotals()
	}

	@objc private func updateTotals() {
		countLabel.title = "\(model.drops.count) Items"
		totalSizeLabel.title = "Total Size: " + diskSizeFormatter.string(fromByteCount: model.sizeInBytes)
	}

	@IBAction func editSelected(_ sender: UIBarButtonItem) {
		isEditing = !isEditing
		sender.title = isEditing ? "Done" : "Edit"
		sender.style = isEditing ? .done : .plain
		archivedItemCollectionView.reloadSections([0])
		updateTotals()
		navigationController?.setToolbarHidden(!isEditing, animated: true)
	}

	@IBAction func resetPressed(_ sender: UIBarButtonItem) {
		sender.isEnabled = false
		archivedItemCollectionView.performBatchUpdates({
			self.model.drops.forEach { $0.delete() }
			self.model.drops.removeAll()
			self.model.save()
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

			if let n = presentedViewController, n.modalPresentationStyle == .popover {
				n.dismiss(animated: false)
			}

			archivedItemCollectionView.performBatchUpdates({})
		}
		lastSize = view.bounds.size
	}

	/////////////////////////////////

	@objc private func deleteDetected(_ notification: Notification) {
		if let item = notification.object as? ArchivedDropItem {
			deleteRequested(for: item)
		}
	}

	func deleteRequested(for item: ArchivedDropItem) {
		if let i = model.filteredDrops.index(where: { $0.uuid == item.uuid }) {
			if let x = model.drops.index(where: { $0.uuid == item.uuid }) {
				model.drops.remove(at: x)
			}
			archivedItemCollectionView.performBatchUpdates({
				self.archivedItemCollectionView.deleteItems(at: [IndexPath(item: i, section: 0)])
			})
		}
		item.delete()
		model.save()
	}

	func loadingProgress(sender: AnyObject) {
		if let i = model.filteredDrops.index(where: { $0 === sender }) {
			let ip = IndexPath(item: i, section: 0)
			if let cell = archivedItemCollectionView.cellForItem(at: ip) as? ArchivedItemCell {
				cell.decorate()
			}
		}
	}

	func loadCompleted(sender: AnyObject, success: Bool) {
		if let i = model.filteredDrops.index(where: { $0 === sender }) {

			if !success, let item = sender as? ArchivedDropItem {
				let (errorPrefix, error) = item.loadingError
				let a = UIAlertController(title: "Some data from \(item.oneTitle) could not be imported", message: "\(errorPrefix ?? "")\(error?.localizedDescription ?? "")", preferredStyle: .alert)
				a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
				(presentedViewController?.presentedViewController ?? presentedViewController ?? self).present(a, animated: true)
			}

			let ip = [IndexPath(item: i, section: 0)]
			archivedItemCollectionView.reloadItems(at: ip)
			model.save() { success in
				(sender as? ArchivedDropItem)?.makeIndex()
			}
		}
	}

	//////////////////////////

	func startSearch(initialText: String) {
		if let s = navigationItem.searchController {
			s.searchBar.text = initialText
			s.isActive = true
		}
	}

	private func resetSearch() {
		if let s = navigationItem.searchController {
			s.searchResultsUpdater = nil
			s.delegate = nil

			model.filter = nil
			s.searchBar.text = nil
			s.isActive = false

			s.searchResultsUpdater = self
			s.delegate = self
		}
	}

	func highlightItem(with identifier: String) {
		resetSearch()
		archivedItemCollectionView.isUserInteractionEnabled = false
		if let i = model.drops.index(where: { $0.uuid.uuidString == identifier }) {
			let ip = IndexPath(item: i, section: 0)
			archivedItemCollectionView.scrollToItem(at: ip, at: [.centeredVertically, .centeredHorizontally], animated: false)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				let cell = self.archivedItemCollectionView.cellForItem(at: ip) as! ArchivedItemCell
				cell.flash()
				self.archivedItemCollectionView.isUserInteractionEnabled = true
			}
		}
	}

	func willDismissSearchController(_ searchController: UISearchController) {
		resetSearch()
	}

	private var searchTimer: PopTimer!

	func updateSearchResults(for searchController: UISearchController) {
		searchTimer.push()
	}

	private var dragActionInProgress = false
	@objc func searchUpdated() {
		archivedItemCollectionView.reloadSections(IndexSet(integer: 0))
	}
}

