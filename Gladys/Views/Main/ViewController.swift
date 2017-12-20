
import UIKit
import CoreSpotlight
import StoreKit
import GladysFramework

func genericAlert(title: String?, message: String?, on viewController: UIViewController, showOK: Bool = true) {
	let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
	if showOK {
		a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
	}

	var finalVC: UIViewController! = viewController
	while finalVC.presentedViewController != nil {
		let newVC = finalVC.presentedViewController
		if newVC is UIAlertController { break }
		finalVC = newVC
	}

	finalVC.present(a, animated: true)

	if !showOK {
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
			a.dismiss(animated: true)
		}
	}
}

final class ViewController: GladysViewController, UICollectionViewDelegate, LoadCompletionDelegate, SKProductsRequestDelegate,
	UISearchControllerDelegate, UISearchResultsUpdating, SKPaymentTransactionObserver, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource,
	UICollectionViewDropDelegate, UICollectionViewDragDelegate, UIPopoverPresentationControllerDelegate {

	@IBOutlet weak var archivedItemCollectionView: UICollectionView!
	@IBOutlet weak var totalSizeLabel: UIBarButtonItem!
	@IBOutlet weak var deleteButton: UIBarButtonItem!
	@IBOutlet weak var editLabelsButton: UIBarButtonItem!
	@IBOutlet weak var labelsButton: UIBarButtonItem!
	@IBOutlet weak var settingsButton: UIBarButtonItem!
	@IBOutlet weak var itemsCount: UIBarButtonItem!
	@IBOutlet weak var dragModePanel: UIView!
	@IBOutlet weak var dragModeButton: UIButton!
	@IBOutlet weak var dragModeTitle: UILabel!

	static var shared: ViewController!

	static var launchQueue = [()->Void]()

	static func executeOrQueue(block: @escaping ()->Void) {
		if shared == nil {
			launchQueue.append(block)
		} else {
			block()
		}
	}

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

	/////////////////////////////

	private var dragModeReverse = false

	private func showDragModeOverlay(_ show: Bool) {
		if dragModePanel.superview != nil, !show {
			UIView.animate(withDuration: 0.2, animations: {
				self.dragModePanel.alpha = 0
				self.dragModePanel.transform = CGAffineTransform(translationX: 0, y: -200)
			}, completion: { finished in
				self.dragModePanel.removeFromSuperview()
				self.dragModePanel.transform = .identity
			})
		} else if dragModePanel.superview == nil, show {
			self.dragModeReverse = false
			self.updateDragModeOverlay()
			view.addSubview(dragModePanel)
			let top = dragModePanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
			top.constant = -200
			NSLayoutConstraint.activate([
				dragModePanel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
				top
				])
			view.layoutIfNeeded()
			top.constant = 0
			UIView.animate(withDuration: 0.2, animations: {
				self.view.layoutIfNeeded()
				self.dragModePanel.alpha = 1
			}, completion: { finished in
			})
		}
	}

	@IBAction func dragModeButtonSelected(_ sender: UIButton) {
		dragModeReverse = !dragModeReverse
		updateDragModeOverlay()
	}

	private func updateDragModeOverlay() {
		if dragModeMove {
			dragModeTitle.text = "Moving"
			dragModeButton.setTitle("Copy instead", for: .normal)
		} else {
			dragModeTitle.text = "Copying"
			dragModeButton.setTitle("Move instead", for: .normal)
		}
	}

	private var dragModeMove: Bool {
		if dragModeReverse {
			return !PersistedOptions.removeItemsWhenDraggedOut
		}
		return PersistedOptions.removeItemsWhenDraggedOut
	}

	/////////////////////////

	func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
		if PersistedOptions.showCopyMoveSwitchSelector {
			showDragModeOverlay(true)
		}
	}

	func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
		showDragModeOverlay(false)
		if let droppedIds = ArchivedDropItemType.droppedIds {
			if dragModeMove {
				let items = droppedIds.flatMap { Model.item(uuid: $0) }
				if items.count > 0 {
					deleteRequested(for: items)
				}
			}
			ArchivedDropItemType.droppedIds = nil
		}
	}

	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		ArchivedDropItemType.droppedIds = Set<UUID>()
		return [Model.filteredDrops[indexPath.item].dragItem]
	}

	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		let newItem = Model.filteredDrops[indexPath.item].dragItem
		if !session.items.contains(newItem) {
			return [newItem]
		} else {
			return []
		}
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return Model.filteredDrops.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ArchivedItemCell", for: indexPath) as! ArchivedItemCell
		cell.lowMemoryMode = lowMemoryMode
		let item = Model.filteredDrops[indexPath.item]
		cell.archivedDropItem = item
		cell.isEditing = isEditing
		cell.isSelectedForAction = selectedItems?.contains(where: { $0 == item.uuid }) ?? false
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
			let newTotal = Model.drops.count + insertCount
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
					let sourceIndex = Model.drops.index(of: existingItem),
					let filteredPreviousIndex = coordinatorItem.sourceIndexPath else { continue }

				let destinationIndex = Model.nearestUnfilteredIndexForFilteredIndex(filteredDestinationIndexPath.item)

				collectionView.performBatchUpdates({
				    Model.drops.remove(at: sourceIndex)
				    Model.drops.insert(existingItem, at: destinationIndex)
				    Model.forceUpdateFilter(signalUpdate: false)
					collectionView.deleteItems(at: [filteredPreviousIndex])
					collectionView.insertItems(at: [filteredDestinationIndexPath])
				})

				coordinator.drop(dragItem, toItemAt: filteredDestinationIndexPath)
				needSave = true

			} else {

				var firstDestinationPath: IndexPath?
				for item in ArchivedDropItem.importData(providers: [dragItem.itemProvider], delegate: self, overrides: nil) {
					var dataIndex = coordinator.destinationIndexPath?.item ?? Model.filteredDrops.count
					let destinationIndexPath = IndexPath(item: dataIndex, section: 0)

					if Model.isFiltering {
						dataIndex = Model.nearestUnfilteredIndexForFilteredIndex(dataIndex)
						if Model.isFilteringLabels && !PersistedOptions.dontAutoLabelNewItems {
							item.labels = Model.enabledLabelsForItems
						}
					}

					var itemVisiblyInserted = false
					collectionView.performBatchUpdates({
						Model.drops.insert(item, at: dataIndex)
						Model.forceUpdateFilter(signalUpdate: false)
						itemVisiblyInserted = Model.filteredDrops.contains(item)
						if itemVisiblyInserted {
							collectionView.isAccessibilityElement = false
							collectionView.insertItems(at: [destinationIndexPath])
						}
					}, completion: { finished in
						self.mostRecentIndexPathActioned = destinationIndexPath
						self.focusInitialAccessibilityElement()
					})

					loadingUUIDs.insert(item.uuid)
					if itemVisiblyInserted {
						firstDestinationPath = destinationIndexPath
					}
				}
				startBgTaskIfNeeded()
				if let firstDestinationPath = firstDestinationPath {
					coordinator.drop(dragItem, toItemAt: firstDestinationPath)
				}
			}
		}

		if needSave{
		    Model.save()
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
		showDragModeOverlay(false)
		resetForDragEntry(session: session)
	}

	func resetForDragEntry(session: UIDropSession) {
		if currentPreferencesView != nil && !session.hasItemsConforming(toTypeIdentifiers: ["build.bru.gladys.archive", "public.zip-archive"]) {
			dismissAnyPopOver()
		} else if currentDetailView != nil || currentLabelSelector != nil {
			dismissAnyPopOver()
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

	var phoneMode: Bool {
		return traitCollection.horizontalSizeClass == .compact || traitCollection.verticalSizeClass == .compact
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
			p.backgroundColor = c

			for n in t.viewControllers ?? [] {
				n.view.backgroundColor = c
			}

		} else if segue.identifier == "showDetail",
			let item = sender as? ArchivedDropItem,
			let index = Model.filteredDrops.index(of: item),
			let n = segue.destination as? UINavigationController,
			let d = n.topViewController as? DetailController,
			let p = n.popoverPresentationController {

			d.item = item
			let indexPath = IndexPath(item: index, section: 0)
			if let cell = archivedItemCollectionView.cellForItem(at: indexPath) {
				let cellRect = cell.convert(cell.bounds.insetBy(dx: 6, dy: 6), to: navigationController!.view)
				p.permittedArrowDirections = [.down, .left, .right]
				p.sourceView =  navigationController!.view
				p.sourceRect = cellRect
				p.delegate = self
				let c = patternColor
				p.backgroundColor = c
				n.view.backgroundColor = c
			}

		} else if segue.identifier == "showLabels",
			let n = segue.destination as? UINavigationController,
			let p = n.popoverPresentationController {

			p.delegate = self
			if isEditing {
				setEditing(false, animated: true)
			}

		} else if segue.identifier == "showLabelEditor",
			let n = segue.destination as? UINavigationController,
			let e = n.topViewController as? LabelEditorController,
			let p = n.popoverPresentationController {

			p.delegate = self
			e.selectedItems = selectedItems
			e.endCallback = { [weak self] hasChanges in
				if hasChanges {
					self?.setEditing(false, animated: true)
				}
			}
		}
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

		if collectionView.hasActiveDrag { return }

		let item = Model.filteredDrops[indexPath.item]
		if item.loadingProgress != nil {
			return
		}

		if isEditing {
			if selectedItems?.index(where: { $0 == item.uuid }) == nil {
				selectedItems?.append(item.uuid)
			} else {
				selectedItems = selectedItems?.filter { $0 != item.uuid }
			}
			didUpdateItems()
			collectionView.reloadItems(at: [indexPath])

		} else {
			mostRecentIndexPathActioned = indexPath
			performSegue(withIdentifier: "showDetail", sender: item)
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		navigationItem.largeTitleDisplayMode = .never
		navigationItem.largeTitleDisplayMode = .automatic
		pasteButton.accessibilityLabel = "Paste from clipboard"
		settingsButton.accessibilityLabel = "Options"

		dragModePanel.translatesAutoresizingMaskIntoConstraints = false
		dragModePanel.layer.shadowColor = UIColor.black.cgColor
		dragModePanel.layer.shadowOffset = CGSize(width: 0, height: 0)
		dragModePanel.layer.shadowOpacity = 0.3
		dragModePanel.layer.shadowRadius = 1
		dragModePanel.alpha = 0
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		ViewController.shared = self

	    Model.beginMonitoringChanges()

		navigationItem.rightBarButtonItems?.insert(editButtonItem, at: 0)

		archivedItemCollectionView.dropDelegate = self
		archivedItemCollectionView.dragDelegate = self
		archivedItemCollectionView.reorderingCadence = .fast
		archivedItemCollectionView.dataSource = self
		archivedItemCollectionView.delegate = self
		archivedItemCollectionView.backgroundView = UIImageView(image: #imageLiteral(resourceName: "paper").resizableImage(withCapInsets: .zero, resizingMode: .tile))
		archivedItemCollectionView.accessibilityLabel = "Items"
		archivedItemCollectionView.dragInteractionEnabled = true

		CSSearchableIndex.default().indexDelegate = Model.indexDelegate

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
		    Model.filter = searchController?.searchBar.text
		}

		navigationController?.setToolbarHidden(true, animated: false)

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(labelSelectionChanged), name: .LabelSelectionChanged, object: nil)
		n.addObserver(self, selector: #selector(reloadData), name: .ItemCollectionNeedsDisplay, object: nil)
		n.addObserver(self, selector: #selector(didUpdateItems), name: .SaveComplete, object: nil)
		n.addObserver(self, selector: #selector(externalDataUpdate), name: .ExternalDataUpdated, object: nil)
		n.addObserver(self, selector: #selector(foregrounded), name: .UIApplicationWillEnterForeground, object: nil)
		n.addObserver(self, selector: #selector(detailViewClosing), name: .DetailViewClosing, object: nil)
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
		if reachability.status == .ReachableViaWiFi && CloudManager.onlySyncOverWiFi {
			CloudManager.opportunisticSyncIfNeeded(isStartup: false)
		}
	}

	@objc private func refreshControlChanged(_ sender: UIRefreshControl) {
		guard let r = archivedItemCollectionView.refreshControl else { return }
		if r.isRefreshing && !CloudManager.syncing {
			CloudManager.sync(overridingWiFiPreference: true) { error in
				if let error = error {
					genericAlert(title: "Sync Error", message: error.finalDescription, on: self)
				}
			}
			lastSyncUpdate()
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
		pasteClipboard(overrides: nil)
	}

	func pasteClipboard(overrides: ImportOverrides?) {
		let providers = UIPasteboard.general.itemProviders
		if providers.count == 0 {
			genericAlert(title: "Nothing To Paste", message: "There is currently nothing in the clipboard.", on: self)
			return
		}

		if checkInfiniteMode(for: 1) {
			return
		}

		for item in ArchivedDropItem.importData(providers: providers, delegate: self, overrides: overrides) {

			if Model.isFilteringLabels && !PersistedOptions.dontAutoLabelNewItems {
				item.labels = Model.enabledLabelsForItems
			}

			let destinationIndexPath = IndexPath(item: 0, section: 0)

			archivedItemCollectionView.performBatchUpdates({
				Model.drops.insert(item, at: 0)
				Model.forceUpdateFilter(signalUpdate: false)
				let itemVisiblyInserted = Model.filteredDrops.contains(item)
				if itemVisiblyInserted {
					archivedItemCollectionView.insertItems(at: [destinationIndexPath])
					archivedItemCollectionView.isAccessibilityElement = false
				}
			}, completion: { finished in
				self.archivedItemCollectionView.scrollToItem(at: destinationIndexPath, at: .centeredVertically, animated: true)
				self.mostRecentIndexPathActioned = destinationIndexPath
				self.focusInitialAccessibilityElement()
			})

			updateEmptyView(animated: true)

			loadingUUIDs.insert(item.uuid)
		}
		startBgTaskIfNeeded()
	}

	@objc private func detailViewClosing() {
		ensureNoEmptySearchResult()
	}

	func sendToTop(item: ArchivedDropItem) {
		if let i = Model.drops.index(of: item) {
			Model.drops.remove(at: i)
			Model.drops.insert(item, at: 0)
			Model.save()
			Model.forceUpdateFilter(signalUpdate: true)
		}
	}

	private func checkForUpgrade() {
		let previousBuild = UserDefaults.standard.string(forKey: "LastRanVersion")
		let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		#if DEBUG
			migration(to: currentBuild)
		#else
			if previousBuild != currentBuild {
				migration(to: currentBuild)
			}
		#endif
	}

	private func migration(to currentBuild: String) {
		if CloudManager.syncSwitchedOn {
			if CloudManager.lastiCloudAccount == nil {
				CloudManager.lastiCloudAccount = FileManager.default.ubiquityIdentityToken
			}
			CloudManager.migrate()
		}
		Model.searchableIndex(CSSearchableIndex.default(), reindexAllSearchableItemsWithAcknowledgementHandler: {
			UserDefaults.standard.set(currentBuild, forKey: "LastRanVersion")
			UserDefaults.standard.synchronize()
		})
	}

	private var lowMemoryMode = false
	override func didReceiveMemoryWarning() {
		if UIApplication.shared.applicationState == .background {
			lowMemoryMode = true
			NotificationCenter.default.post(name: .LowMemoryModeOn, object: nil)
			log("Placed UI in low-memory mode")
		}
		ArchivedItemCell.clearCaches()
		super.didReceiveMemoryWarning()
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
		var shouldSaveInAnyCase = false
		for item in Model.drops.filter({ !$0.needsDeletion }) { // partial deletes
			let componentsToDelete = item.typeItems.filter { $0.needsDeletion }
			if componentsToDelete.count > 0 {
				item.typeItems = item.typeItems.filter { !$0.needsDeletion }
				for c in componentsToDelete {
					c.deleteFromStorage()
				}
				item.needsReIngest = true
				shouldSaveInAnyCase = !CloudManager.syncing // this could be from the file provider
			}
		}
		let itemsToDelete = Model.drops.filter { $0.needsDeletion }
		if itemsToDelete.count > 0 {
			deleteRequested(for: itemsToDelete) // will also save
		} else if shouldSaveInAnyCase {
			Model.save()
		}
	}

	@objc private func externalDataUpdate() {
	    Model.forceUpdateFilter(signalUpdate: false) // will force below
		reloadData()
		detectExternalDeletions()
		didUpdateItems()
		updateEmptyView(animated: true)
	}

	private var emptyView: UIImageView?
	@objc private func didUpdateItems() {
		editButtonItem.isEnabled = Model.drops.count > 0

		selectedItems = selectedItems?.filter { uuid in Model.drops.contains(where: { $0.uuid == uuid }) }

		let count = (selectedItems?.count ?? 0)

		let c = count == 0 ? Model.drops.count : count
		itemsCount.title = c > 1 ? "\(c) Items" : c == 1 ? "1 Item" : "No Items"

		let size = count == 0 ? Model.sizeInBytes : Model.sizeForItems(uuids: selectedItems ?? [])
		totalSizeLabel.title = diskSizeFormatter.string(fromByteCount: size)
		deleteButton.isEnabled = count > 0
		editLabelsButton.isEnabled = count > 0

		let itemsToReIngest = Model.drops.filter { $0.needsReIngest && $0.loadingProgress == nil && !$0.isDeleting && !loadingUUIDs.contains($0.uuid) }
		for item in itemsToReIngest {
			loadingUUIDs.insert(item.uuid)
			startBgTaskIfNeeded()
			ArchivedItemCell.clearCachedImage(for: item)
			item.reIngest(delegate: self)
		}

		updateLabelIcon()
		currentLabelEditor?.selectedItems = selectedItems
		archivedItemCollectionView.isAccessibilityElement = Model.filteredDrops.count == 0
	}

	@objc private func labelSelectionChanged() {
	    Model.forceUpdateFilter(signalUpdate: true)
		updateLabelIcon()
	}

	private func updateLabelIcon() {
		if Model.isFilteringLabels {
			labelsButton.image = #imageLiteral(resourceName: "labels-selected")
			labelsButton.accessibilityLabel = "Labels"
			labelsButton.accessibilityValue = "Active"
			title = Model.enabledLabelsForTitles.joined(separator: ", ")
		} else {
			labelsButton.image = #imageLiteral(resourceName: "labels-unselected")
			labelsButton.accessibilityLabel = "Labels"
			labelsButton.accessibilityValue = "Inactive"
			title = "Gladys"
		}
		labelsButton.isEnabled = Model.drops.count > 0
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

			NSLayoutConstraint.activate([
				l.topAnchor.constraint(equalTo: e.bottomAnchor, constant: 8),
				l.centerXAnchor.constraint(equalTo: e.centerXAnchor),
				l.widthAnchor.constraint(equalTo: e.widthAnchor),
			])

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
		if Model.drops.count == 0 && emptyView == nil {
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

		} else if let e = emptyView, Model.drops.count > 0 {
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
			selectedItems = [UUID]()
		} else {
			selectedItems = nil
			deleteButton.isEnabled = false
		}

		UIView.performWithoutAnimation {
			didUpdateItems()
			for cell in archivedItemCollectionView.visibleCells as? [ArchivedItemCell] ?? [] {
				cell.isEditing = editing
			}
		}
	}

	var itemSize = CGSize.zero
	private func calculateItemSize() {

		func calculateSizes(for columnCount: CGFloat) {
			let layout = (archivedItemCollectionView.collectionViewLayout as! UICollectionViewFlowLayout)
			let extras = (layout.minimumInteritemSpacing * (columnCount - 1.0)) + layout.sectionInset.left + layout.sectionInset.right
			let side = ((lastSize.width - extras) / columnCount).rounded(.down)
			itemSize = CGSize(width: side, height: side)
		}

		if lastSize.width <= 320 && !PersistedOptions.forceTwoColumnPreference {
			itemSize = CGSize(width: 300, height: 200)
		} else if lastSize.width >= 1024 {
			calculateSizes(for: 4)
		} else if lastSize.width >= 694 {
			calculateSizes(for: 3)
		} else {
			calculateSizes(for: 2)
		}
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		return itemSize
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
			CloudManager.opportunisticSyncIfNeeded(isStartup: true)
			DispatchQueue.main.async {
				ViewController.launchQueue.forEach { $0() }
				ViewController.launchQueue.removeAll(keepingCapacity: false)
			}
		}
	}

	private var lastSize = CGSize.zero
	func forceLayout() {
		lastSize = .zero
		view.setNeedsLayout()
	}
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		let boundsSize = view.bounds.size
		if lastSize == boundsSize { return }
		lastSize = boundsSize

		calculateItemSize()

		archivedItemCollectionView.performBatchUpdates({})
	}

	/////////////////////////////////

	private var selectedItems: [UUID]?
	@IBAction func deleteButtonSelected(_ sender: UIBarButtonItem) {
		guard let candidates = selectedItems, candidates.count > 0 else { return }

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
		guard let candidates = selectedItems, candidates.count > 0 else { return }

		let itemsToDelete = Model.drops.filter { item -> Bool in
			candidates.contains(where: { $0 == item.uuid })
		}
		if itemsToDelete.count > 0 {
			deleteRequested(for: itemsToDelete)
		}

		selectedItems?.removeAll()
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

	private var currentLabelEditor: LabelEditorController? {
		return firstPresentedNavigationController?.viewControllers.first as? LabelEditorController
	}

	private var currentDetailView: DetailController? {
		return firstPresentedNavigationController?.viewControllers.first as? DetailController
	}

	private var currentPreferencesView: PreferencesController? {
		return firstPresentedNavigationController?.viewControllers.first as? PreferencesController
	}

	private var currentLabelSelector: LabelSelector? {
		return firstPresentedNavigationController?.viewControllers.first as? LabelSelector
	}

	func dismissAnyPopOver(completion: (()->Void)? = nil) {
		if let p = navigationItem.searchController?.presentedViewController ?? navigationController?.presentedViewController, let pc = p.popoverPresentationController {
			if popoverPresentationControllerShouldDismissPopover(pc) {
				firstPresentedNavigationController?.viewControllers.first?.dismiss(animated: true) {
					completion?()
				}
				return
			}
		}
		completion?()
	}

	func deleteRequested(for items: [ArchivedDropItem]) {

		for item in items {

			if item.shouldDisplayLoading {
				item.cancelIngest()
			}

			let uuid = item.uuid
			loadingUUIDs.remove(uuid)

			if let i = Model.filteredDrops.index(where: { $0.uuid == uuid }) {
			    Model.removeItemFromList(uuid: uuid)
				archivedItemCollectionView.performBatchUpdates({
					self.archivedItemCollectionView.deleteItems(at: [IndexPath(item: i, section: 0)])
				})
			}

			item.delete()
		}

	    Model.save()

		ensureNoEmptySearchResult()

		if Model.filteredDrops.count == 0 {
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
	    Model.forceUpdateFilter(signalUpdate: true)
		if Model.filteredDrops.count == 0 && Model.isFiltering {
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

	func loadCompleted(sender: AnyObject) {

		guard let item = sender as? ArchivedDropItem else { return }

		if let (errorPrefix, error) = item.loadingError {
			genericAlert(title: "Some data from \(item.oneTitle) could not be imported",
				message: errorPrefix + error.finalDescription,
				on: self)
		}

		item.needsReIngest = false

		if let i = Model.filteredDrops.index(of: item) {
			mostRecentIndexPathActioned = IndexPath(item: i, section: 0)
			archivedItemCollectionView.reloadItems(at: [mostRecentIndexPathActioned!])
			focusInitialAccessibilityElement()
			item.reIndex()
		} else {
			item.reIndex {
				DispatchQueue.main.async { // if item is still invisible after re-indexing, let the user know
					if !Model.forceUpdateFilter(signalUpdate: true) {
						if item.createdAt == item.updatedAt {
							genericAlert(title: "Item(s) Added", message: nil, on: self, showOK: false)
						}
					}
				}
			}
		}

		loadingUUIDs.remove(item.uuid)
		if loadingUUIDs.count == 0 {
			Model.save()
			UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil)
		}

		endBgTaskIfNeeded()
	}

	//////////////////////////

	func startSearch(initialText: String) {
		if let s = navigationItem.searchController {
			s.searchBar.text = initialText
			s.isActive = true
		}
	}

	private func resetSearch(andLabels: Bool) {
		guard let s = navigationItem.searchController else { return }
		s.searchResultsUpdater = nil
		s.delegate = nil
		s.searchBar.text = nil
		s.isActive = false

		if andLabels {
			Model.disableAllLabels()
			updateLabelIcon()
		}

		if Model.filter == nil { // because the next line won't have any effect if it's already nil
			Model.forceUpdateFilter(signalUpdate: true)
		} else {
			Model.filter = nil
		}

		s.searchResultsUpdater = self
		s.delegate = self
	}

	func highlightItem(with identifier: String, andOpen: Bool) {
		resetSearch(andLabels: true)
		dismissAnyPopOver()
		archivedItemCollectionView.isUserInteractionEnabled = false
		if let i = Model.drops.index(where: { $0.uuid.uuidString == identifier }) {
			let ip = IndexPath(item: i, section: 0)
			archivedItemCollectionView.scrollToItem(at: ip, at: [.centeredVertically, .centeredHorizontally], animated: false)
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				if let cell = self.archivedItemCollectionView.cellForItem(at: ip) as? ArchivedItemCell {
					cell.flash()
					if andOpen {
						self.collectionView(self.archivedItemCollectionView, didSelectItemAt: ip)
					}
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

	@objc func reloadData() {
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
		log("Error fetching IAP items: \(error.finalDescription)")
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

		if Model.isFiltering {
			resetSearch(andLabels: true)
		}
		dismissAnyPopOver()

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
		             message: error.finalDescription,
		             on: self)
	}

	func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
		for t in transactions.filter({ $0.payment.productIdentifier == "INFINITE" }) {
			switch t.transactionState {
			case .failed:
				SKPaymentQueue.default().finishTransaction(t)
				genericAlert(title: "There was an error completing this purchase",
				             message: t.error?.finalDescription,
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
		let t = (controller.presentedViewController as? UINavigationController)?.topViewController
		if t is LabelSelector || t is LabelEditorController {
			return .none
		} else {
			return .overCurrentContext
		}
	}

	///////////////////////////// Quick actions

	func forceStartSearch() {
		dismissAnyPopOver() {
			if let s = self.navigationItem.searchController, !s.isActive {
				s.searchBar.becomeFirstResponder()
			}
		}
	}

	func forcePaste() {
		resetSearch(andLabels: true)
		dismissAnyPopOver()
		pasteSelected(pasteButton)
	}

	///////////////////////////// Accessibility

	private var mostRecentIndexPathActioned: IndexPath?

	private var closestIndexPathSinceLast: IndexPath? {
		let count = Model.filteredDrops.count
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
