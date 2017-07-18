
import UIKit
import CoreSpotlight
import StoreKit
import GladysFramework

final class ViewController: UIViewController, UICollectionViewDelegate,
	ArchivedItemCellDelegate, LoadCompletionDelegate, SKProductsRequestDelegate,
	UISearchControllerDelegate, UISearchResultsUpdating, SKPaymentTransactionObserver,
	UICollectionViewDelegateFlowLayout, UICollectionViewDataSource,
	UICollectionViewDropDelegate, UICollectionViewDragDelegate, UIPopoverPresentationControllerDelegate {

	@IBOutlet weak var archivedItemCollectionView: UICollectionView!
	@IBOutlet weak var totalSizeLabel: UIBarButtonItem!
	@IBOutlet weak var deleteButton: UIBarButtonItem!

	private let model = Model()

	static var shared: ViewController!

	///////////////////////

	private var bgTask: UIBackgroundTaskIdentifier?
	private func startBgTask() {
		log("Starting background ingest task")
		bgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.gladys.ingestTask", expirationHandler: nil)
	}
	private func endBgTask() {
		if let b = bgTask {
			log("Ending background ingest task")
			UIApplication.shared.endBackgroundTask(b)
			bgTask = nil
		}
	}

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
		cell.lowMemoryMode = lowMemoryMode
		let item = model.filteredDrops[indexPath.item]
		cell.archivedDropItem = item
		cell.isEditing = isEditing
		cell.isSelectedForDelete = deletionCandidates?.contains(where: { $0 == item.uuid }) ?? false
		cell.delegate = self
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

		let insertCount = countInserts(in: coordinator.session)
		if !model.infiniteMode && insertCount > 0 {

			let newTotal = model.drops.count + insertCount
			if newTotal > model.nonInfiniteItemLimit {
				displayIAPRequest(newTotal: newTotal)
				return
			}
		}

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

				let item = ArchivedDropItem(providers: [dragItem.itemProvider], delegate: self)
				let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: model.drops.count, section: 0)

				collectionView.performBatchUpdates({
					self.model.drops.insert(item, at: destinationIndexPath.item)
					collectionView.insertItems(at: [destinationIndexPath])
				})

				loadCount += 1
				coordinator.drop(dragItem, toItemAt: destinationIndexPath)
			}
		}

		if needSave{
			model.needsSave = true
		} else {
			updateEmptyView(animated: true)
		}
	}

	private var loadCount = 0 {
		didSet {
			if loadCount > 0 && bgTask == nil {
				startBgTask()
			} else if loadCount == 0 && bgTask != nil {
				endBgTask()
			}
		}
	}

	func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
		return true
	}

	private func countInserts(in session: UIDropSession) -> Int {
		return session.items.reduce(0) { count, item in
			if item.localObject == nil {
				return count + 1
			}
			return count
		}
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidEnter session: UIDropSession) {
		if countInserts(in: session) > 0 {
			resetSearch()
		}
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		if countInserts(in: session) > 0 {
			return UICollectionViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
		} else {
			if model.isFiltering {
				return UICollectionViewDropProposal(operation: .forbidden)
			} else {
				return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
			}
		}
	}

	private var dimView: UIView?
	func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
		if let d = dimView {
			dimView = nil
			UIView.animate(animations: {
				d.alpha = 0
			}) { finished in
				d.removeFromSuperview()
			}
		}
		return true
	}
	func prepareForPopoverPresentation(_ popoverPresentationController: UIPopoverPresentationController) {
		if dimView == nil {
			let d = UIView(frame: .zero)
			d.backgroundColor = UIColor(white: 0, alpha: 0.3)
			d.alpha = 0
			navigationController?.view.cover(with: d)
			dimView = d
			UIView.animate(animations: {
				d.alpha = 1
			})
		}
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		let item = model.filteredDrops[indexPath.item]
		if item.isLoading {
			return
		}

		if isEditing {
			if deletionCandidates?.index(where: { $0 == item.uuid }) == nil {
				deletionCandidates?.append(item.uuid)
			} else {
				deletionCandidates = deletionCandidates?.filter { $0 != item.uuid }
			}
			didUpdateItems()
			collectionView.reloadItems(at: [indexPath])
			return
		}

		let n = storyboard?.instantiateViewController(withIdentifier: "DetailController") as! UINavigationController
		let d = n.topViewController as! DetailController
		d.item = item
		n.modalPresentationStyle = .popover
		navigationController?.visibleViewController?.present(n, animated: true)
		if let p = n.popoverPresentationController, let cell = collectionView.cellForItem(at: indexPath) {
			p.permittedArrowDirections = [.any]
			p.sourceView = cell
			p.sourceRect = cell.bounds.insetBy(dx: 5, dy: 0)
			p.delegate = self
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

		navigationItem.rightBarButtonItem = editButtonItem

		archivedItemCollectionView.dropDelegate = self
		archivedItemCollectionView.dragDelegate = self
		archivedItemCollectionView.reorderingCadence = .immediate
		archivedItemCollectionView.dataSource = self
		archivedItemCollectionView.delegate = self
		archivedItemCollectionView.backgroundView = UIImageView(image: #imageLiteral(resourceName: "paper").resizableImage(withCapInsets: .zero, resizingMode: .tile))

		CSSearchableIndex.default().indexDelegate = model

		navigationController?.navigationBar.titleTextAttributes = [
			NSAttributedStringKey.foregroundColor.rawValue: UIColor.lightGray
		]
		navigationController?.navigationBar.largeTitleTextAttributes = [
			.foregroundColor: UIColor.lightGray
		]

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
		n.addObserver(self, selector: #selector(didUpdateItems), name: .SaveComplete, object: nil)
		n.addObserver(self, selector: #selector(deleteDetected(_:)), name: .DeleteSelected, object: nil)
		n.addObserver(self, selector: #selector(externalDataUpdate), name: .ExternalDataUpdated, object: nil)
		n.addObserver(self, selector: #selector(foregrounded), name: .UIApplicationWillEnterForeground, object: nil)

		didUpdateItems()
		updateEmptyView(animated: false)
		blurb("Ready! Drop me stuff.")

		SKPaymentQueue.default().add(self)
		fetchIap()
	}

	private var lowMemoryMode = false
	override func didReceiveMemoryWarning() {
		if UIApplication.shared.applicationState == .background {
			lowMemoryMode = true
			NotificationCenter.default.post(name: .LowMemoryModeOn, object: nil)
		}
	}

	@objc private func foregrounded() {
		if lowMemoryMode {
			lowMemoryMode = false
			for cell in archivedItemCollectionView.visibleCells as? [ArchivedItemCell] ?? [] {
				cell.lowMemoryMode = false
				cell.reDecorate()
			}
		}

		if emptyView != nil {
			blurb(randomGreetLine)
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@objc private func externalDataUpdate() {
		if model.isFiltering {
			model.filter = nil
			model.filter = self.navigationItem.searchController?.searchBar.text
		} else {
			archivedItemCollectionView.reloadData()
		}
		didUpdateItems()
		updateEmptyView(animated: true)
	}

	private var emptyView: UIImageView?
	@objc private func didUpdateItems() {
		totalSizeLabel.title = "\(model.drops.count) Items: " + diskSizeFormatter.string(fromByteCount: model.sizeInBytes)
		editButtonItem.isEnabled = model.drops.count > 0

		let count = (deletionCandidates?.count ?? 0)
		deleteButton.isEnabled = count > 0
		if count > 1 {
			deleteButton.title = "Delete \(count) Items"
		} else {
			deleteButton.title = "Delete"
		}
	}

	private func blurb(_ message: String) {
		if let e = emptyView {
			let l = UILabel()
			l.translatesAutoresizingMaskIntoConstraints = false
			l.font = UIFont.preferredFont(forTextStyle: .caption2)
			l.textColor = .darkGray
			l.textAlignment = .center
			l.text = message
			l.numberOfLines = 0
			l.lineBreakMode = .byWordWrapping
			view.addSubview(l)
			l.topAnchor.constraint(equalTo: e.bottomAnchor, constant: 8).isActive = true
			l.centerXAnchor.constraint(equalTo: e.centerXAnchor).isActive = true
			l.widthAnchor.constraint(equalTo: e.widthAnchor).isActive = true

			UIView.animate(withDuration: 1, delay: 3, options: .curveEaseInOut, animations: {
				l.alpha = 0
			}, completion: { finished in
				l.removeFromSuperview()
			})
		}
	}

	private func updateEmptyView(animated: Bool) {
		if model.drops.count == 0 && emptyView == nil {
			let e = UIImageView(frame: .zero)
			e.contentMode = .center
			e.image = #imageLiteral(resourceName: "gladysImage").limited(to: CGSize(width: 160, height: 160), limitTo: 1, useScreenScale: true)
			e.center(on: view)
			emptyView = e

			if animated {
				e.alpha = 0
				UIView.animate(animations: {
					e.alpha = 1
				})
			}

		} else if let e = emptyView, model.drops.count > 0 {
			emptyView = nil
			if animated {
				UIView.animate(animations: {
					e.alpha = 0
				}) { finished in
					e.removeFromSuperview()
				}
			} else {
				e.removeFromSuperview()
			}
		}
	}

	override func setEditing(_ editing: Bool, animated: Bool) {
		super.setEditing(editing, animated: animated)

		navigationController?.setToolbarHidden(!editing, animated: animated)
		if editing {
			deletionCandidates = [UUID]()
		} else {
			deletionCandidates = nil
			deleteButton.isEnabled = false
		}

		UIView.performWithoutAnimation {
			didUpdateItems()
			for cell in archivedItemCollectionView.visibleCells as? [ArchivedItemCell] ?? [] {
				cell.isEditing = editing
			}
		}
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
				if let d = dimView {
					d.removeFromSuperview()
					dimView = nil
				}
			}

			archivedItemCollectionView.performBatchUpdates({})
		}
		lastSize = view.bounds.size
	}

	/////////////////////////////////

	private var deletionCandidates: [UUID]?
	@IBAction func deleteButtonSelected(_ sender: UIBarButtonItem) {
		guard let candidates = deletionCandidates else { return }
		deletionCandidates?.removeAll()

		let itemsToDelete = model.drops.filter { item -> Bool in
			candidates.contains(where: { $0 == item.uuid })
		}
		if itemsToDelete.count > 0 {
			deleteRequested(for: itemsToDelete)
		}
	}

	@objc private func deleteDetected(_ notification: Notification) {
		if let item = notification.object as? ArchivedDropItem {
			deleteRequested(for: [item])
		}
	}

	func deleteRequested(for items: [ArchivedDropItem]) {
		for item in items {
			let uuid = item.uuid
			if let i = model.filteredDrops.index(where: { $0.uuid == uuid }) {
				model.removeItemFromList(uuid: uuid)
				archivedItemCollectionView.performBatchUpdates({
					self.archivedItemCollectionView.deleteItems(at: [IndexPath(item: i, section: 0)])
				})
			}
			item.delete()
		}
		if model.filteredDrops.count == 0 {
			updateEmptyView(animated: true)
			if isEditing {
				view.layoutIfNeeded()
				setEditing(false, animated: true)
				blurb(randomCleanLine)
			}
		}
		model.needsSave = true
	}

	private var randomCleanLine: String {
		let count = UInt32(ViewController.cleanLines.count)
		return ViewController.cleanLines[Int(arc4random_uniform(count))]
	}
	private static let cleanLines = [
		"Tidy!",
		"Woosh!",
		"Spotless!",
		"Clean desk!",
		"Neeext!",
		"Peekaboo!",
		"Cool!",
		"Zap!",
		"Feels all empty now!",
		"So much space!",
	]

	private var randomGreetLine: String {
		let count = UInt32(ViewController.greetLines.count)
		return ViewController.greetLines[Int(arc4random_uniform(count))]
	}
	private static let greetLines = [
		"Drop me more stuff!",
		"What's next?",
		"Hey there.",
		"Hi boss!",
		"Feed me!",
		"What's up?",
		"What can I hold for you?",
		"Gimme.",
		"How can I help?",
		"Ready!",
		]

	func loadingProgress(sender: AnyObject) {
		if let i = model.filteredDrops.index(where: { $0 === sender }) {
			let ip = IndexPath(item: i, section: 0)
			if let cell = archivedItemCollectionView.cellForItem(at: ip) as? ArchivedItemCell {
				cell.reDecorate()
			}
		}
	}

	func loadCompleted(sender: AnyObject, success: Bool) {

		if let item = sender as? ArchivedDropItem {
			if !success {
				let (errorPrefix, error) = item.loadingError
				if errorPrefix != nil || error != nil {
					let a = UIAlertController(title: "Some data from \(item.oneTitle) could not be imported", message: "\(errorPrefix ?? "")\(error?.localizedDescription ?? "")", preferredStyle: .alert)
					a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
					(presentedViewController?.presentedViewController ?? presentedViewController ?? self).present(a, animated: true)
				}
			}

			item.makeIndex()

			if let i = model.filteredDrops.index(where: { $0 === sender }) {
				let ip = [IndexPath(item: i, section: 0)]
				archivedItemCollectionView.reloadItems(at: ip)
			}

			loadCount -= 1
			if loadCount == 0 {
				model.needsSave = true
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
		archivedItemCollectionView.performBatchUpdates({
			self.archivedItemCollectionView.reloadSections(IndexSet(integer: 0))
		}, completion: nil)
	}

	/////////////////////////////

	private var iapFetchCallbackCount: Int?
	private var infiniteModeItem: SKProduct?

	private func fetchIap() {
		if !model.infiniteMode {
			let r = SKProductsRequest(productIdentifiers: ["INFINITE"])
			r.delegate = self
			r.start()
		}
	}

	func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
		infiniteModeItem = response.products.first
		iapFetchCompletion()
	}

	func request(_ request: SKRequest, didFailWithError error: Error) {
		log("Error fetching IAP items: \(error.localizedDescription)")
		iapFetchCompletion()
	}

	private func iapFetchCompletion() {
		if let c = iapFetchCallbackCount {
			iapFetchCallbackCount = nil
			displayIAPRequest(newTotal: c)
		}
	}

	func displayIAPRequest(newTotal: Int) {

		guard model.infiniteMode == false else { return }

		guard let infiniteModeItem = infiniteModeItem else {
			let message = "That operation would result in a total of \(newTotal) items, and Gladys will hold up to \(model.nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time in-app purchase.\n\nWe cannot seem to fetch the in-app purchase information at this time. Please check your internet connection and try again in a moment."
			let a = UIAlertController(title: "Gladys Unlimited", message: message, preferredStyle: .alert)
			a.addAction(UIAlertAction(title: "Try Again", style: .default, handler: { action in
				self.iapFetchCallbackCount = newTotal
				self.fetchIap()
			}))
			a.addAction(UIAlertAction(title: "Later", style: .cancel))
			present(a, animated: true) {
				self.fetchIap()
			}
			return
		}

		let f = NumberFormatter()
		f.numberStyle = .currency
		f.locale = infiniteModeItem.priceLocale
		let infiniteModeItemPrice = f.string(from: infiniteModeItem.price)!
		let message = "That operation would result in a total of \(newTotal) items, and Gladys will hold up \(model.nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time purchase of \(infiniteModeItemPrice)"

		let a = UIAlertController(title: "Gladys Unlimited", message: message, preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "Buy for \(infiniteModeItemPrice)", style: .destructive, handler: { action in
			let payment = SKPayment(product: infiniteModeItem)
			SKPaymentQueue.default().add(payment)
		}))
		a.addAction(UIAlertAction(title: "Restore previous purchase.", style: .default, handler: { action in
			SKPaymentQueue.default().restoreCompletedTransactions()
		}))
		a.addAction(UIAlertAction(title: "It's OK, I'll delete older stuff", style: .cancel))
		present(a, animated: true)
	}

	private func displayIapSuccess() {
		let a = UIAlertController(title: "You can now add unlimited items!", message: "Thank you for supporting Gladys!", preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
		present(a, animated: true)
	}

	func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
		if !model.infiniteMode {
			let a = UIAlertController(title: "Purchase could not be restored", message: "Are you sure you purchased this from the App Store account that you are currently using?", preferredStyle: .alert)
			a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
			present(a, animated: true)
		}
	}

	func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
		let a = UIAlertController(title: "There was an error restoring your purchase", message: error.localizedDescription, preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
		present(a, animated: true)
	}

	func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
		for t in transactions.filter({ $0.payment.productIdentifier == "INFINITE" }) {
			switch t.transactionState {
			case .failed:
				SKPaymentQueue.default().finishTransaction(t)
				let a = UIAlertController(title: "There was an error completing this purchase", message: t.error?.localizedDescription, preferredStyle: .alert)
				a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
				present(a, animated: true)
				SKPaymentQueue.default().finishTransaction(t)
			case .purchased, .restored:
				model.infiniteMode = verifyIapReceipt()
				SKPaymentQueue.default().finishTransaction(t)
				displayIapSuccess()
			case .purchasing, .deferred:
				break
			}
		}
	}
}

