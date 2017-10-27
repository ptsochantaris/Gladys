
import UIKit
import CoreSpotlight
import StoreKit
import GladysFramework

func genericAlert(title: String?, message: String?, on viewController: UIViewController) {
	let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
	a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

	var finalVC: UIViewController! = viewController
	while finalVC.presentedViewController != nil {
		finalVC = finalVC.presentedViewController
	}
	finalVC.present(a, animated: true)
}

final class ViewController: GladysViewController, UICollectionViewDelegate,
	LoadCompletionDelegate, SKProductsRequestDelegate,
	UISearchControllerDelegate, UISearchResultsUpdating, SKPaymentTransactionObserver,
	UICollectionViewDelegateFlowLayout, UICollectionViewDataSource,
	UICollectionViewDropDelegate, UICollectionViewDragDelegate, UIPopoverPresentationControllerDelegate {

	@IBOutlet weak var archivedItemCollectionView: UICollectionView!
	@IBOutlet weak var totalSizeLabel: UIBarButtonItem!
	@IBOutlet weak var deleteButton: UIBarButtonItem!
	@IBOutlet weak var labelsButton: UIBarButtonItem!
	@IBOutlet weak var settingsButton: UIBarButtonItem!

	static var shared: ViewController!

	///////////////////////

	private var bgTask: UIBackgroundTaskIdentifier?
	private func startBgTaskIfNeeded() {
		if bgTask == nil {
			log("Starting background ingest task")
			bgTask = UIApplication.shared.beginBackgroundTask(withName: "build.bru.gladys.ingestTask", expirationHandler: nil)
		}
	}
	private func endBgTaskIfNeeded() {
		if loadingUUIDs.count == 0, let b = bgTask {
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
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
		let center = cell.center
		let x = center.x
		let y = center.y
		let w = cell.frame.size.width
		cell.accessibilityDropPointDescriptors = [
			UIAccessibilityLocationDescriptor(name: "Drop after item", point: CGPoint(x: x + w, y: y), in: collectionView),
			UIAccessibilityLocationDescriptor(name: "Drop before item", point: CGPoint(x: x - w, y: y), in: collectionView)
		]
	}

	private func checkInfiniteMode(for insertCount: Int) -> Bool {
		if !infiniteMode && insertCount > 0 {
			let newTotal = model.drops.count + insertCount
			if newTotal > nonInfiniteItemLimit {
				displayIAPRequest(newTotal: newTotal)
				return true
			}
		}
		return false
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

		if checkInfiniteMode(for: countInserts(in: coordinator.session)) {
			return
		}

		var needSave = false

		coordinator.session.progressIndicatorStyle = .none

		for coordinatorItem in coordinator.items {
			let dragItem = coordinatorItem.dragItem

			if let existingItem = dragItem.localObject as? ArchivedDropItem {

				guard
					let filteredDestinationIndexPath = coordinator.destinationIndexPath,
					let sourceIndex = model.drops.index(of: existingItem),
					let filteredPreviousIndex = coordinatorItem.sourceIndexPath else { continue }

				let destinationIndex = model.nearestUnfilteredIndexForFilteredIndex(filteredDestinationIndexPath.item)

				collectionView.performBatchUpdates({
					model.drops.remove(at: sourceIndex)
					model.drops.insert(existingItem, at: destinationIndex)
					model.forceUpdateFilter(signalUpdate: false)
					collectionView.deleteItems(at: [filteredPreviousIndex])
					collectionView.insertItems(at: [filteredDestinationIndexPath])
				})

				coordinator.drop(dragItem, toItemAt: filteredDestinationIndexPath)
				needSave = true

			} else {

				let item = ArchivedDropItem(providers: [dragItem.itemProvider], delegate: self)
				var dataIndex = coordinator.destinationIndexPath?.item ?? model.filteredDrops.count
				let destinationIndexPath = IndexPath(item: dataIndex, section: 0)

				if model.isFilteringLabels {
					dataIndex = model.nearestUnfilteredIndexForFilteredIndex(dataIndex)
					item.labels = model.enabledLabelsForItems
				}

				collectionView.performBatchUpdates({
					collectionView.isAccessibilityElement = false
					model.drops.insert(item, at: dataIndex)
					model.forceUpdateFilter(signalUpdate: false)
					collectionView.insertItems(at: [destinationIndexPath])
				}, completion: { finished in
					self.mostRecentIndexPathActioned = destinationIndexPath
					self.focusInitialAccessibilityElement()
				})

				loadingUUIDs.insert(item.uuid)
				startBgTaskIfNeeded()
				coordinator.drop(dragItem, toItemAt: destinationIndexPath)
			}
		}

		if needSave{
			model.save()
		} else {
			updateEmptyView(animated: true)
		}
	}

	private var loadingUUIDs = Set<UUID>()

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
		resetForDragEntry(session: session)
	}

	func resetForDragEntry(session: UIDropSession) {
		if currentDetailView != nil || currentLabelSelector != nil {
			dismissAnyPopOver()
		}
		if countInserts(in: session) > 0 {
			resetSearch(andLabels: false)
		}
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		return UICollectionViewDropProposal(operation: operation(for: session), intent: .insertAtDestinationIndexPath)
	}

	private func operation(for session: UIDropSession) -> UIDropOperation {
		return countInserts(in: session) > 0 ? .copy : .move
	}

	private var dimView: DimView?
	func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
		if let d = dimView {
			dimView = nil
			d.dismiss()
		}

		return true
	}
	func prepareForPopoverPresentation(_ popoverPresentationController: UIPopoverPresentationController) {
		if dimView == nil {
			let d = DimView()
			navigationController?.view.cover(with: d)
			dimView = d
			if !(navigationItem.searchController?.isActive ?? false) {
				popoverPresentationController.passthroughViews = [d]
			}
		}
	}

	private var patternColor: UIColor {
		return UIColor(patternImage: (archivedItemCollectionView.backgroundView as! UIImageView).image!)
	}

	private var phoneMode: Bool {
		return traitCollection.horizontalSizeClass == .regular || traitCollection.verticalSizeClass == .regular
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

		if segue.identifier == "showPreferences",
			let t = segue.destination as? UITabBarController,
			let p = t.popoverPresentationController {

			p.permittedArrowDirections = [.any]
			p.sourceRect = CGRect(origin: CGPoint(x: 15, y: 15), size: CGSize(width: 44, height: 44))
			p.sourceView = navigationController!.view
			p.delegate = self

			let c = patternColor

			for n in t.viewControllers ?? [] {
				if let d = (n as? UINavigationController)?.topViewController {
					if phoneMode {
						n.view.backgroundColor = c
					} else {
						p.backgroundColor = c
						d.navigationItem.rightBarButtonItem = nil
					}
				}
			}

		} else if segue.identifier == "showDetail",
			let item = sender as? ArchivedDropItem,
			let index = model.filteredDrops.index(of: item),
			let n = segue.destination as? UINavigationController,
			let d = n.topViewController as? DetailController,
			let p = n.popoverPresentationController {

			d.item = item
			let indexPath = IndexPath(item: index, section: 0)
			if let cell = archivedItemCollectionView.cellForItem(at: indexPath) {
				p.permittedArrowDirections = [.down, .left, .right]
				p.sourceView = cell
				p.sourceRect = cell.bounds.insetBy(dx: 6, dy: 6)
				p.delegate = self
				let c = patternColor
				if phoneMode {
					n.view.backgroundColor = c
				} else {
					p.backgroundColor = c
					d.navigationItem.rightBarButtonItem = nil
				}
			}

		} else if segue.identifier == "showLabels",
			let n = segue.destination as? UINavigationController,
			let p = n.popoverPresentationController {

			p.delegate = self
			if isEditing {
				setEditing(false, animated: true)
			}
		}
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

		if collectionView.hasActiveDrag { return }

		let item = model.filteredDrops[indexPath.item]
		if item.loadingProgress != nil {
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

		} else {
			mostRecentIndexPathActioned = indexPath
			performSegue(withIdentifier: "showDetail", sender: item)
		}
	}

	@objc private func itemPositionsReceived() {
		if let sequence = CloudManager.uuidSequence {
			model.drops.sort { i1, i2 in
				let p1 = sequence.index(of: i1.uuid.uuidString) ?? 0
				let p2 = sequence.index(of: i2.uuid.uuidString) ?? 0
				return p1 < p2
			}
			NotificationCenter.default.post(name: .ExternalDataUpdated, object: nil)
			model.save()
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		navigationItem.largeTitleDisplayMode = .never
		navigationItem.largeTitleDisplayMode = .automatic
		pasteButton.accessibilityLabel = "Paste from clipboard"
		settingsButton.accessibilityLabel = "Options"
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		ViewController.shared = self

		model.beginMonitoringChanges()

		navigationItem.rightBarButtonItems?.insert(editButtonItem, at: 0)

		archivedItemCollectionView.dropDelegate = self
		archivedItemCollectionView.dragDelegate = self
		archivedItemCollectionView.reorderingCadence = .immediate
		archivedItemCollectionView.dataSource = self
		archivedItemCollectionView.delegate = self
		archivedItemCollectionView.backgroundView = UIImageView(image: #imageLiteral(resourceName: "paper").resizableImage(withCapInsets: .zero, resizingMode: .tile))
		archivedItemCollectionView.accessibilityLabel = "Items"
		archivedItemCollectionView.dragInteractionEnabled = true

		CSSearchableIndex.default().indexDelegate = model

		navigationController?.navigationBar.titleTextAttributes = [
			.foregroundColor: UIColor.lightGray
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

		searchTimer = PopTimer(timeInterval: 0.4) { [weak searchController] in
			model.filter = searchController?.searchBar.text
		}

		navigationController?.setToolbarHidden(true, animated: false)

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(labelSelectionChanged), name: .LabelSelectionChanged, object: nil)
		n.addObserver(self, selector: #selector(searchUpdated), name: .SearchResultsUpdated, object: nil)
		n.addObserver(self, selector: #selector(didUpdateItems), name: .SaveComplete, object: nil)
		n.addObserver(self, selector: #selector(externalDataUpdate), name: .ExternalDataUpdated, object: nil)
		n.addObserver(self, selector: #selector(foregrounded), name: .UIApplicationWillEnterForeground, object: nil)
		n.addObserver(self, selector: #selector(detailViewClosing), name: .DetailViewClosing, object: nil)
		n.addObserver(self, selector: #selector(itemPositionsReceived), name: .CloudManagerUpdatedUUIDSequence, object: nil)
		n.addObserver(self, selector: #selector(cloudStatusChanged), name: .CloudManagerStatusChanged, object: nil)
		n.addObserver(self, selector: #selector(reachabilityChanged), name: .ReachabilityChanged, object: nil)

		didUpdateItems()
		updateEmptyView(animated: false)
		blurb("Ready! Drop me stuff.")

		SKPaymentQueue.default().add(self)
		fetchIap()

		checkForUpgrade()
		cloudStatusChanged()
	}

	@objc private func reachabilityChanged() {
		if CloudManager.syncSwitchedOn && reachability.status == .ReachableViaWiFi && CloudManager.onlySyncOverWiFi {
			CloudManager.tryManualSync(from: self)
		}
	}

	@objc private func refreshControlChanged(_ sender: UIRefreshControl) {
		guard let r = archivedItemCollectionView.refreshControl else { return }
		if r.isRefreshing && !CloudManager.syncing {
			CloudManager.tryManualSync(from: self)
		} else {
			r.beginRefreshing()
		}
	}

	@objc private func cloudStatusChanged() {
		if CloudManager.syncSwitchedOn && archivedItemCollectionView.refreshControl == nil {
			let refresh = UIRefreshControl()
			refresh.tintColor = view.tintColor
			refresh.addTarget(self, action: #selector(refreshControlChanged(_:)), for: .valueChanged)
			archivedItemCollectionView.refreshControl = refresh

			navigationController?.view.layoutIfNeeded()

		} else if !CloudManager.syncSwitchedOn && archivedItemCollectionView.refreshControl != nil {
			archivedItemCollectionView.refreshControl = nil
		}

		if let r = archivedItemCollectionView.refreshControl {
			if r.isRefreshing && !CloudManager.syncing {
				r.endRefreshing()
			}
			lastSyncUpdate()
		}
	}

	private func lastSyncUpdate() {
		if let r = archivedItemCollectionView.refreshControl {
			r.attributedTitle = NSAttributedString(string: CloudManager.syncString)
		}
	}

	func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		lastSyncUpdate()
	}

	@IBOutlet weak var pasteButton: UIBarButtonItem!

	@IBAction func pasteSelected(_ sender: UIBarButtonItem) {

		let providers = UIPasteboard.general.itemProviders
		if providers.count == 0 {
			genericAlert(title: "Nothing To Paste", message: "There is currently nothing in the clipboard.", on: self)
			return
		}

		if checkInfiniteMode(for: 1) {
			return
		}

		let item = ArchivedDropItem(providers: providers, delegate: self)

		if model.isFilteringLabels {
			item.labels = model.enabledLabelsForItems
		}

		let destinationIndexPath = IndexPath(item: 0, section: 0)

		archivedItemCollectionView.performBatchUpdates({
			model.drops.insert(item, at: 0)
			model.forceUpdateFilter(signalUpdate: false)
			archivedItemCollectionView.insertItems(at: [destinationIndexPath])
		}, completion: { finished in
			self.archivedItemCollectionView.scrollToItem(at: destinationIndexPath, at: .centeredVertically, animated: true)
			self.mostRecentIndexPathActioned = destinationIndexPath
			self.focusInitialAccessibilityElement()
		})

		updateEmptyView(animated: true)

		loadingUUIDs.insert(item.uuid)
		startBgTaskIfNeeded()
	}

	@objc private func detailViewClosing() {
		ensureNoEmptySearchResult()
	}

	private func checkForUpgrade() {
		let previousBuild = UserDefaults.standard.string(forKey: "LastRanVersion")
		let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		if previousBuild != currentBuild {
			model.searchableIndex(CSSearchableIndex.default(), reindexAllSearchableItemsWithAcknowledgementHandler: {
				UserDefaults.standard.set(currentBuild, forKey: "LastRanVersion")
				UserDefaults.standard.synchronize()
			})
		}
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

	private func detectExternalDeletions() {
		let itemsToDelete = model.drops.filter { $0.needsDeletion }
		if itemsToDelete.count > 0 {
			deleteRequested(for: itemsToDelete)
		}
	}

	@objc private func externalDataUpdate() {
		model.forceUpdateFilter(signalUpdate: false) // will force below
		searchUpdated()
		didUpdateItems()
		updateEmptyView(animated: true)
		detectExternalDeletions()
	}

	private var emptyView: UIImageView?
	@objc private func didUpdateItems() {
		totalSizeLabel.title = "\(model.drops.count) Items: " + diskSizeFormatter.string(fromByteCount: model.sizeInBytes)
		editButtonItem.isEnabled = model.drops.count > 0

		deletionCandidates = deletionCandidates?.filter { uuid in model.drops.contains(where: { $0.uuid == uuid }) }

		let count = (deletionCandidates?.count ?? 0)
		deleteButton.isEnabled = count > 0
		if count > 1 {
			deleteButton.title = "Delete \(count) Items"
		} else {
			deleteButton.title = "Delete"
		}

		let itemsToReIngest = model.drops.filter { $0.needsReIngest && $0.loadingProgress == nil && !$0.isDeleting }
		for item in itemsToReIngest {
			loadingUUIDs.insert(item.uuid)
			startBgTaskIfNeeded()
			item.reIngest(delegate: self)
		}

		updateLabelIcon()
		archivedItemCollectionView.isAccessibilityElement = model.filteredDrops.count == 0
	}

	@objc private func labelSelectionChanged() {
		model.forceUpdateFilter(signalUpdate: true)
		updateLabelIcon()
	}

	private func updateLabelIcon() {
		if model.isFilteringLabels {
			labelsButton.image = #imageLiteral(resourceName: "labels-selected")
			labelsButton.accessibilityLabel = "Labels"
			labelsButton.accessibilityValue = "Active"
			title = model.enabledLabelsForTitles.joined(separator: ", ")
		} else {
			labelsButton.image = #imageLiteral(resourceName: "labels-unselected")
			labelsButton.accessibilityLabel = "Labels"
			labelsButton.accessibilityValue = "Inactive"
			title = "Gladys"
		}
		labelsButton.isEnabled = model.drops.count > 0
	}

	private func blurb(_ message: String) {
		if let e = emptyView, !view.subviews.contains(where: { $0.tag == 9265 }) {
			let l = UILabel()
			l.tag = 9265
			l.translatesAutoresizingMaskIntoConstraints = false
			l.font = UIFont.preferredFont(forTextStyle: .caption2)
			l.textColor = .darkGray
			l.textAlignment = .center
			l.text = message
			l.numberOfLines = 0
			l.lineBreakMode = .byWordWrapping
			l.isAccessibilityElement = false
			view.addSubview(l)
			l.topAnchor.constraint(equalTo: e.bottomAnchor, constant: 8).isActive = true
			l.centerXAnchor.constraint(equalTo: e.centerXAnchor).isActive = true
			l.widthAnchor.constraint(equalTo: e.widthAnchor).isActive = true

			DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
				UIView.animate(withDuration: 1, delay: 0, options: .curveEaseInOut, animations: {
					l.alpha = 0
				}, completion: { finished in
					l.removeFromSuperview()
				})
			}
		}
	}

	private func updateEmptyView(animated: Bool) {
		if model.drops.count == 0 && emptyView == nil {
			let e = UIImageView(frame: .zero)
			e.isAccessibilityElement = false
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

	private func dragParameters(for indexPath: IndexPath) -> UIDragPreviewParameters? {
		if let cell = archivedItemCollectionView.cellForItem(at: indexPath) as? ArchivedItemCell, let b = cell.backgroundView {
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

	func collectionView(_ collectionView: UICollectionView, dropPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
		return dragParameters(for: indexPath)
	}

	private var firstAppearance = true
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if firstAppearance {
			firstAppearance = false
			archivedItemCollectionView.refreshControl?.tintColor = view.tintColor
			detectExternalDeletions()
			CloudManager.sync { error in
				if let error = error {
					log("Error in foregrounding sync: \(error.localizedDescription)")
				}
			}
		}
	}

	private var lastSize = CGSize.zero
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		let boundsSize = view.bounds.size
		if lastSize == boundsSize { return }
		lastSize = boundsSize

		dismissAnyPopOver()
		archivedItemCollectionView.performBatchUpdates({})
	}

	/////////////////////////////////

	private var deletionCandidates: [UUID]?
	@IBAction func deleteButtonSelected(_ sender: UIBarButtonItem) {
		guard let candidates = deletionCandidates, candidates.count > 0 else { return }

		let a = UIAlertController(title: "Please Confirm", message: nil, preferredStyle: .actionSheet)
		let msg = candidates.count > 1 ? "Delete \(candidates.count) Items" : "Delete Item"
		a.addAction(UIAlertAction(title: msg, style: .destructive, handler: { action in
			if let p = a.popoverPresentationController {
				_ = self.popoverPresentationControllerShouldDismissPopover(p)
			}
			self.proceedWithDelete()
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		a.modalPresentationStyle = .popover
		navigationController?.visibleViewController?.present(a, animated: true)
		if let p = a.popoverPresentationController {
			p.permittedArrowDirections = [.any]
			p.sourceRect = CGRect(origin: CGPoint(x: 0, y: view.bounds.size.height-44), size: CGSize(width: 100, height: 44))
			p.sourceView = navigationController!.view
			p.delegate = self
		}
	}

	private func proceedWithDelete() {
		guard let candidates = deletionCandidates, candidates.count > 0 else { return }

		let itemsToDelete = model.drops.filter { item -> Bool in
			candidates.contains(where: { $0 == item.uuid })
		}
		if itemsToDelete.count > 0 {
			deleteRequested(for: itemsToDelete)
		}

		deletionCandidates?.removeAll()
	}

	private var firstPresentedNavigationController: UINavigationController? {
		let v = presentedViewController?.presentedViewController?.presentedViewController ?? presentedViewController?.presentedViewController ?? presentedViewController
		if let v = v as? UINavigationController {
			return v
		} else if let v = v as? UITabBarController {
			return v.selectedViewController as? UINavigationController
		}
		return nil
	}

	private var currentDetailView: DetailController? {
		return firstPresentedNavigationController?.topViewController as? DetailController
	}

	private var currentLabelSelector: LabelSelector? {
		return firstPresentedNavigationController?.topViewController as? LabelSelector
	}

	func dismissAnyPopOver() {
		if let p = navigationItem.searchController?.presentedViewController ?? navigationController?.presentedViewController, let pc = p.popoverPresentationController {
			if popoverPresentationControllerShouldDismissPopover(pc) {
				firstPresentedNavigationController?.dismiss(animated: true)
			}
		}
	}

	func deleteRequested(for items: [ArchivedDropItem]) {

		var detailController = currentDetailView

		for item in items {

			if item.shouldDisplayLoading {
				item.cancelIngest()
			}

			let uuid = item.uuid

			if let d = detailController, d.item.uuid == uuid {
				d.done()
				detailController = nil
			}

			if let i = model.filteredDrops.index(where: { $0.uuid == uuid }) {
				model.removeItemFromList(uuid: uuid)
				archivedItemCollectionView.performBatchUpdates({
					self.archivedItemCollectionView.deleteItems(at: [IndexPath(item: i, section: 0)])
				})
			}

			item.delete()
		}

		model.save()

		ensureNoEmptySearchResult()

		if model.filteredDrops.count == 0 {
			mostRecentIndexPathActioned = nil
			updateEmptyView(animated: true)
			if isEditing {
				view.layoutIfNeeded()
				setEditing(false, animated: true)
			}
			blurb(randomCleanLine)
		} else {
			if isEditing {
				setEditing(false, animated: true)
			}
		}

		focusInitialAccessibilityElement()
	}

	private func ensureNoEmptySearchResult() {
		model.forceUpdateFilter(signalUpdate: true)
		if model.filteredDrops.count == 0 && (model.isFilteringText || model.isFilteringLabels) {
			resetSearch(andLabels: true)
		}
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
		"Nice!",
		"Feels all empty now!",
		"Very Zen!",
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
		"Quiet day?",
		"How can I help?",
		"Howdy!",
		"Ready!",
	]

	func loadCompleted(sender: AnyObject, success: Bool) {

		if let item = sender as? ArchivedDropItem {
			if !success {
				let (errorPrefix, error) = item.loadingError
				if errorPrefix != nil || error != nil {
					genericAlert(title: "Some data from \(item.oneTitle) could not be imported",
						message: "\(errorPrefix ?? "")\(error?.localizedDescription ?? "")",
						on: self)
				}
			}

			item.needsReIngest = false
			item.makeIndex()

			if let i = model.filteredDrops.index(where: { $0 === sender }) {
				mostRecentIndexPathActioned = IndexPath(item: i, section: 0)
				archivedItemCollectionView.reloadItems(at: [mostRecentIndexPathActioned!])
				focusInitialAccessibilityElement()
			}

			loadingUUIDs.remove(item.uuid)
			if loadingUUIDs.count == 0 {
				model.save()
				UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil)
			}

			endBgTaskIfNeeded()
		}
	}

	//////////////////////////

	func startSearch(initialText: String) {
		if let s = navigationItem.searchController {
			s.searchBar.text = initialText
			s.isActive = true
		}
	}

	private func resetSearch(andLabels: Bool) {
		if let s = navigationItem.searchController {
			s.searchResultsUpdater = nil
			s.delegate = nil

			if andLabels {
				model.disableAllLabels()
				updateLabelIcon()
				if model.filter == nil { // because the next line won't have any effect if its already nil
					model.forceUpdateFilter(signalUpdate: true)
				}
			}

			model.filter = nil
			s.searchBar.text = nil
			s.isActive = false

			s.searchResultsUpdater = self
			s.delegate = self
		}
	}

	func highlightItem(with identifier: String) {
		resetSearch(andLabels: true)
		archivedItemCollectionView.isUserInteractionEnabled = false
		if let i = model.drops.index(where: { $0.uuid.uuidString == identifier }) {
			let ip = IndexPath(item: i, section: 0)
			archivedItemCollectionView.scrollToItem(at: ip, at: [.centeredVertically, .centeredHorizontally], animated: false)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				if let cell = self.archivedItemCollectionView.cellForItem(at: ip) as? ArchivedItemCell {
					cell.flash()
				}
				self.archivedItemCollectionView.isUserInteractionEnabled = true
			}
		}
	}

	func willDismissSearchController(_ searchController: UISearchController) {
		resetSearch(andLabels: false)
	}

	private var searchTimer: PopTimer!

	func updateSearchResults(for searchController: UISearchController) {
		searchTimer.push()
	}

	private var dragActionInProgress = false
	@objc func searchUpdated() {
		updateLabelIcon()
		archivedItemCollectionView.performBatchUpdates({
			self.archivedItemCollectionView.reloadSections(IndexSet(integer: 0))
		})
	}

	///////////////////////////// IAP

	private var iapFetchCallbackCount: Int?
	private var infiniteModeItem: SKProduct?

	private func fetchIap() {
		if !infiniteMode {
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

		guard infiniteMode == false else { return }

		guard let infiniteModeItem = infiniteModeItem else {
			let message: String
			if newTotal == -1 {
				message = "We cannot seem to fetch the in-app purchase information at this time. Please check your Internet connection and try again in a moment."
			} else {
				message = "That operation would result in a total of \(newTotal) items, and Gladys will hold up to \(nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or you can expand Gladys to hold unlimited items with a one-time in-app purchase.\n\nWe cannot seem to fetch the in-app purchase information at this time. Please check your internet connection and try again in a moment."
			}
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
		let message: String
		if newTotal == -1 {
			message = "You can expand Gladys to hold unlimited items with a one-time purchase of \(infiniteModeItemPrice)"
		} else {
			message = "That operation would result in a total of \(newTotal) items, and Gladys will hold up to \(nonInfiniteItemLimit).\n\nYou can delete older stuff to make space, or expand Gladys to hold unlimited items with a one-time purchase of \(infiniteModeItemPrice)"
		}

		let a = UIAlertController(title: "Gladys Unlimited", message: message, preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "Buy for \(infiniteModeItemPrice)", style: .destructive, handler: { action in
			let payment = SKPayment(product: infiniteModeItem)
			SKPaymentQueue.default().add(payment)
		}))
		a.addAction(UIAlertAction(title: "Restore previous purchase", style: .default, handler: { action in
			SKPaymentQueue.default().restoreCompletedTransactions()
		}))
		if newTotal == -1 {
			a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
		} else {
			a.addAction(UIAlertAction(title: "Never mind, I'll delete old stuff", style: .cancel))
		}
		present(a, animated: true)
	}

	private func displayIapSuccess() {
		genericAlert(title: "You can now add unlimited items!",
		             message: "Thank you for supporting Gladys!",
		             on: self)
	}

	func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
		if !infiniteMode {
			genericAlert(title: "Purchase could not be restored",
			             message: "Are you sure you purchased this from the App Store account that you are currently using?",
			             on: self)
		}
	}

	func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
		genericAlert(title: "There was an error restoring your purchase",
		             message: error.localizedDescription,
		             on: self)
	}

	func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
		for t in transactions.filter({ $0.payment.productIdentifier == "INFINITE" }) {
			switch t.transactionState {
			case .failed:
				SKPaymentQueue.default().finishTransaction(t)
				genericAlert(title: "There was an error completing this purchase",
				             message: t.error?.localizedDescription,
				             on: self)
				SKPaymentQueue.default().finishTransaction(t)
			case .purchased, .restored:
				infiniteMode = verifyIapReceipt()
				SKPaymentQueue.default().finishTransaction(t)
				displayIapSuccess()
			case .purchasing, .deferred:
				break
			}
		}
	}

	func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		if let n = controller.presentedViewController as? UINavigationController, n.topViewController is LabelSelector {
			return .none
		} else {
			return .overCurrentContext
		}
	}

	///////////////////////////// Accessibility

	private var mostRecentIndexPathActioned: IndexPath?

	private var closestIndexPathSinceLast: IndexPath? {
		let count = model.filteredDrops.count
		if count == 0 {
			return nil
		}
		guard let mostRecentIndexPathActioned = mostRecentIndexPathActioned else { return nil }
		if count > mostRecentIndexPathActioned.item {
			return mostRecentIndexPathActioned
		}
		return IndexPath(item: count-1, section: 0)
	}

	override var initialAccessibilityElement: UIView {
		if let ip = closestIndexPathSinceLast, let cell = archivedItemCollectionView.cellForItem(at: ip) {
			return cell
		} else {
			return archivedItemCollectionView
		}
	}
}

final class ShowDetailSegue: UIStoryboardSegue {
	override func perform() {
		(source.presentedViewController ?? source).present(destination, animated: true)
	}
}
