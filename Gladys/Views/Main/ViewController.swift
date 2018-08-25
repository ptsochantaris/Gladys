
import UIKit
import CoreSpotlight
import GladysFramework

enum PasteResult {
	case success, noData, tooManyItems
}

@discardableResult
func genericAlert(title: String?, message: String?, showOK: Bool = true, autoDismiss: Bool = true, completion: (()->Void)? = nil) -> UIAlertController {
	let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
	if showOK {
		a.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completion?() }))
	}

	ViewController.top.present(a, animated: true)

	if !showOK && autoDismiss {
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
			a.dismiss(animated: true, completion: completion)
		}
	}

	return a
}

func getInput(from: UIViewController, title: String, action: String, previousValue: String?, completion: @escaping (String?)->Void) {
	let a = UIAlertController(title: title, message: nil, preferredStyle: .alert)
	a.addTextField { textField in
		textField.placeholder = title
		textField.text = previousValue
	}
	a.addAction(UIAlertAction(title: action, style: .default, handler: { ac in
		let result = a.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		completion(result)
	}))
	a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { ac in
		completion(nil)
	}))
	from.present(a, animated: true)
}

let mainWindow: UIWindow = {
	return UIApplication.shared.windows.first!
}()

final class ViewController: GladysViewController, UICollectionViewDelegate, ItemIngestionDelegate, UICollectionViewDataSourcePrefetching,
	UISearchControllerDelegate, UISearchResultsUpdating, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource,
UICollectionViewDropDelegate, UICollectionViewDragDelegate, UIPopoverPresentationControllerDelegate {

	@IBOutlet private weak var collection: UICollectionView!
	@IBOutlet private weak var totalSizeLabel: UIBarButtonItem!
	@IBOutlet private weak var deleteButton: UIBarButtonItem!
	@IBOutlet private weak var editLabelsButton: UIBarButtonItem!
	@IBOutlet private weak var sortAscendingButton: UIBarButtonItem!
	@IBOutlet private weak var sortDescendingButton: UIBarButtonItem!
	@IBOutlet private weak var labelsButton: UIBarButtonItem!
	@IBOutlet private weak var settingsButton: UIBarButtonItem!
	@IBOutlet private weak var itemsCount: UIBarButtonItem!
	@IBOutlet private weak var dragModePanel: UIView!
	@IBOutlet private weak var dragModeButton: UIButton!
	@IBOutlet private weak var dragModeTitle: UILabel!

	static var shared: ViewController!

	static var launchQueue = [()->Void]()

	static func executeOrQueue(block: @escaping ()->Void) {
		if shared == nil {
			launchQueue.append(block)
		} else {
			block()
		}
	}

	static var top: UIViewController {
		let searchController = ViewController.shared.navigationItem.searchController
		let searching = searchController?.isActive ?? false
		var finalVC: UIViewController = (searching ? searchController : nil) ?? ViewController.shared
		while let newVC = finalVC.presentedViewController {
			if newVC is UIAlertController { break }
			finalVC = newVC
		}
		return finalVC
	}

	var itemView: UICollectionView {
		return collection!
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
		if Model.doneIngesting, let b = bgTask {
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
				self.dragModePanel.transform = CGAffineTransform(translationX: 0, y: -300)
			}, completion: { finished in
				self.dragModePanel.removeFromSuperview()
				self.dragModePanel.transform = .identity
			})
		} else if dragModePanel.superview == nil, show {
			dragModeReverse = false
			if PersistedOptions.darkMode {
				dragModePanel.tintColor = self.navigationController?.navigationBar.tintColor
				dragModePanel.backgroundColor = ViewController.darkColor
				dragModeTitle.textColor = .white
			}
			updateDragModeOverlay()
			view.addSubview(dragModePanel)
			let top = dragModePanel.topAnchor.constraint(equalTo: collection.topAnchor)
			top.constant = -300
			NSLayoutConstraint.activate([
				dragModePanel.centerXAnchor.constraint(equalTo: collection.centerXAnchor),
				top
				])
			view.layoutIfNeeded()
			top.constant = -70
			UIView.animate(withDuration: 0.2, animations: {
				self.view.layoutIfNeeded()
				self.dragModePanel.alpha = 1
			}, completion: { finished in
			})
		}
	}

	@IBAction private func dragModeButtonSelected(_ sender: UIButton) {
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
			if let context = session.localDragSession?.localContext as? String, context == "typeItem" {
				endMergeMode()
			} else {
				showDragModeOverlay(true)
			}
		}
	}

	func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
		showDragModeOverlay(false)
		if let droppedIds = ArchivedDropItemType.droppedIds {
			if dragModeMove {
				let items = droppedIds.compactMap { Model.item(uuid: $0) }
				if items.count > 0 {
					deleteRequested(for: items)
				}
			}
			ArchivedDropItemType.droppedIds = nil
		}
	}

	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		ArchivedDropItemType.droppedIds = Set<UUID>()
		let item = Model.filteredDrops[indexPath.item]
		if item.needsUnlock { return [] }
		return [item.dragItem]
	}

	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		let item = Model.filteredDrops[indexPath.item]
		let dragItem = item.dragItem
		if session.localContext as? String == "typeItem" || session.items.contains(dragItem) || item.needsUnlock {
			return []
		} else {
			return [dragItem]
		}
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return Model.filteredDrops.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ArchivedItemCell", for: indexPath) as! ArchivedItemCell
		if indexPath.item < Model.filteredDrops.count {
			cell.lowMemoryMode = lowMemoryMode
			let item = Model.filteredDrops[indexPath.item]
			cell.archivedDropItem = item
			cell.isEditing = isEditing
			cell.isSelectedForAction = selectedItems?.contains(where: { $0 == item.uuid }) ?? false
		}
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
		for indexPath in indexPaths {
			ArchivedItemCell.warmUp(for: Model.filteredDrops[indexPath.item])
		}
	}

	func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {

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

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

		endMergeMode()

		if IAPManager.shared.checkInfiniteMode(for: countInserts(in: coordinator.session)) {
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

			} else if let d = coordinator.destinationIndexPath,
				let cell = willBeMerge(at: d, from: coordinator.session),
				let typeItem = dragItem.localObject as? ArchivedDropItemType {

				let item = Model.filteredDrops[d.item]
				let itemCopy = ArchivedDropItemType(from: typeItem, newParent: item)
				item.typeItems.append(itemCopy)
				item.needsReIngest = true
				item.renumberTypeItems()
				item.markUpdated()
				needSave = true

				let p = CGPoint(x: cell.bounds.midX-44, y: cell.bounds.midY-22)
				coordinator.drop(dragItem, intoItemAt: d, rect: CGRect(origin: p, size: CGSize(width: 88, height: 44)))

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

	func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
		showDragModeOverlay(false)
		endMergeMode()
	}

	private func endMergeMode() {
		if let m = mergeCellIndexPath {
			if let oldCell = collection.cellForItem(at: m) as? ArchivedItemCell {
				oldCell.mergeMode = false
			}
			mergeCellIndexPath = nil
		}
	}

	func resetForDragEntry(session: UIDropSession) {
		if currentPreferencesView != nil && !session.hasItemsConforming(toTypeIdentifiers: ["build.bru.gladys.archive", "public.zip-archive"]) {
			dismissAnyPopOver()
		} else if currentDetailView != nil || currentLabelSelector != nil {
			dismissAnyPopOver()
		}
	}

	private var mergeCellIndexPath: IndexPath?

	private func willBeMerge(at destinationIndexPath: IndexPath?, from session: UIDropSession) -> ArchivedItemCell? {
		if let destinationIndexPath = destinationIndexPath,
			PersistedOptions.allowMergeOfTypeItems,
			let draggedItem = session.items.first?.localObject as? ArchivedDropItemType,
			let cell = collection.cellForItem(at: destinationIndexPath) as? ArchivedItemCell,
			let cellItem = cell.archivedDropItem,
			cellItem.shareMode != .elsewhereReadOnly,
			!cellItem.shouldDisplayLoading && !cellItem.needsUnlock,
			!cellItem.typeItems.contains(where: { $0.uuid == draggedItem.uuid }) {

			return cell
		}

		return nil
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {

		if let context = session.localDragSession?.localContext as? String, context == "typeItem", PersistedOptions.allowMergeOfTypeItems {

			if let cell = willBeMerge(at: destinationIndexPath, from: session) {
				if let m = mergeCellIndexPath, let oldCell = collectionView.cellForItem(at: m) as? ArchivedItemCell {
					oldCell.mergeMode = false
				}
				cell.mergeMode = true
				mergeCellIndexPath = destinationIndexPath
				return UICollectionViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)

			} else if destinationIndexPath != nil {
				endMergeMode()
				return UICollectionViewDropProposal(operation: .forbidden, intent: .unspecified)
			}
		}

		// normal insert
		endMergeMode()
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
		return UIColor(patternImage: (collection.backgroundView as! UIImageView).image!)
	}

	var phoneMode: Bool {
		return traitCollection.horizontalSizeClass == .compact || traitCollection.verticalSizeClass == .compact
	}

	static let imageLightBackground = #colorLiteral(red: 0.8431372549, green: 0.831372549, blue: 0.8078431373, alpha: 1)

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

		switch segue.identifier {

		case "showPreferences":
			guard let t = segue.destination as? UITabBarController,
				let p = t.popoverPresentationController
				else { return }

			p.permittedArrowDirections = [.any]
			p.sourceRect = CGRect(origin: CGPoint(x: 15, y: 15), size: CGSize(width: 44, height: 44))
			p.sourceView = navigationController!.view
			p.delegate = self

			let c = patternColor
			p.backgroundColor = c

			for n in t.viewControllers ?? [] {
				n.view.backgroundColor = c
			}

		case "showDetail":
			guard let item = sender as? ArchivedDropItem,
				let indexPath = mostRecentIndexPathActioned,
				let n = segue.destination as? UINavigationController,
				let d = n.topViewController as? DetailController,
				let p = n.popoverPresentationController,
				let cell = collection.cellForItem(at: indexPath)
				else { return }

			d.item = item

			let c = patternColor
			n.view.backgroundColor = c

			let cellRect = cell.convert(cell.bounds.insetBy(dx: 6, dy: 6), to: navigationController!.view)
			p.permittedArrowDirections = [.down, .left, .right]
			p.sourceView =  navigationController!.view
			p.sourceRect = cellRect
			p.delegate = self
			p.backgroundColor = c

		case "showLabels":
			guard let n = segue.destination as? UINavigationController,
				let p = n.popoverPresentationController
				else { return }

			p.delegate = self
			if PersistedOptions.darkMode {
				p.backgroundColor = ViewController.darkColor
			}
			if isEditing {
				setEditing(false, animated: true)
			}

		case "showLabelEditor":
			guard let n = segue.destination as? UINavigationController,
				let e = n.topViewController as? LabelEditorController,
				let p = n.popoverPresentationController
				else { return }

			p.delegate = self
			if PersistedOptions.darkMode {
				p.backgroundColor = ViewController.darkColor
			}
			e.selectedItems = selectedItems
			e.endCallback = { [weak self] hasChanges in
				if hasChanges {
					self?.setEditing(false, animated: true)
				}
			}

		default: break
		}
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

		if collectionView.hasActiveDrag { return }

		let item = Model.filteredDrops[indexPath.item]
		if item.shouldDisplayLoading {
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

		} else if item.needsUnlock {
			mostRecentIndexPathActioned = indexPath
			item.unlock(from: ViewController.top, label: "Unlock Item", action: "Unlock") { success in
				if success {
					item.needsUnlock = false
					collectionView.reloadItems(at: [indexPath])
				}
			}

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
		dragModePanel.layer.cornerRadius = 100
		dragModePanel.alpha = 0
	}

	@objc override func darkModeChanged() {
		super.darkModeChanged()

		if PersistedOptions.darkMode {
			collection.backgroundView = UIImageView(image: #imageLiteral(resourceName: "darkPaper").resizableImage(withCapInsets: .zero, resizingMode: .tile))
			if let t = navigationItem.searchController?.searchBar.subviews.first?.subviews.first(where: { $0 is UITextField }) as? UITextField {
				DispatchQueue.main.async {
					t.textColor = .lightGray
				}
			}
		} else {
			collection.backgroundView = UIImageView(image: #imageLiteral(resourceName: "paper").resizableImage(withCapInsets: .zero, resizingMode: .tile))
			if let t = navigationItem.searchController?.searchBar.subviews.first?.subviews.first(where: { $0 is UITextField }) as? UITextField {
				DispatchQueue.main.async {
					t.textColor = .darkText
				}
			}
		}

		if let nav = firstPresentedNavigationController {
			nav.popoverPresentationController?.backgroundColor = patternColor
			nav.tabBarController?.viewControllers?.forEach {
				$0.view.backgroundColor = patternColor
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		ViewController.shared = self

	    Model.beginMonitoringChanges()

		navigationItem.rightBarButtonItems?.insert(editButtonItem, at: 0)

		collection.reorderingCadence = .fast
		collection.accessibilityLabel = "Items"
		collection.dragInteractionEnabled = true

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

		darkModeChanged()
		
		searchTimer = PopTimer(timeInterval: 0.4) { [weak searchController, weak self] in
		    Model.filter = searchController?.searchBar.text
			self?.didUpdateItems()
		}

		navigationController?.setToolbarHidden(true, animated: false)

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(labelSelectionChanged), name: .LabelSelectionChanged, object: nil)
		n.addObserver(self, selector: #selector(reloadData), name: .ItemCollectionNeedsDisplay, object: nil)
		n.addObserver(self, selector: #selector(didUpdateItems), name: .SaveComplete, object: nil)
		n.addObserver(self, selector: #selector(externalDataUpdate), name: .ExternalDataUpdated, object: nil)
		n.addObserver(self, selector: #selector(foregrounded), name: UIApplication.willEnterForegroundNotification, object: nil)
		n.addObserver(self, selector: #selector(detailViewClosing), name: .DetailViewClosing, object: nil)
		n.addObserver(self, selector: #selector(cloudStatusChanged), name: .CloudManagerStatusChanged, object: nil)
		n.addObserver(self, selector: #selector(reachabilityChanged), name: .ReachabilityChanged, object: nil)
		n.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
		n.addObserver(self, selector: #selector(acceptStarted), name: .AcceptStarting, object: nil)
		n.addObserver(self, selector: #selector(acceptEnded), name: .AcceptEnding, object: nil)

		didUpdateItems()
		updateEmptyView(animated: false)
		emptyView?.alpha = PersistedOptions.darkMode ? 0.5 : 1
		blurb("Ready! Drop me stuff.")

		checkForUpgrade()
		cloudStatusChanged()
	}

	private var acceptAlert: UIAlertController?

	@objc private func acceptStarted() {
		acceptAlert = genericAlert(title: "Accepting Share...", message: nil, showOK: false, autoDismiss: false, completion: nil)
	}

	@objc private func acceptEnded() {
		acceptAlert?.dismiss(animated: true)
		acceptAlert = nil
	}

	@objc private func backgrounded() {
		Model.lockUnlockedItems()
	}

	@objc private func reachabilityChanged() {
		if reachability.status == .ReachableViaWiFi && CloudManager.onlySyncOverWiFi {
			CloudManager.opportunisticSyncIfNeeded(isStartup: false)
		}
	}

	@objc private func refreshControlChanged(_ sender: UIRefreshControl) {
		guard let r = collection.refreshControl else { return }
		if r.isRefreshing && !CloudManager.syncing {
			CloudManager.sync(overridingWiFiPreference: true) { error in
				if let error = error {
					genericAlert(title: "Sync Error", message: error.finalDescription)
				}
			}
			lastSyncUpdate()
		}
	}

	@objc private func cloudStatusChanged() {
		if CloudManager.syncSwitchedOn && collection.refreshControl == nil {
			let refresh = UIRefreshControl()
			refresh.tintColor = view.tintColor
			refresh.addTarget(self, action: #selector(refreshControlChanged(_:)), for: .valueChanged)
			collection.refreshControl = refresh

			navigationController?.view.layoutIfNeeded()

		} else if !CloudManager.syncSwitchedOn && collection.refreshControl != nil {
			collection.refreshControl = nil
		}

		if let r = collection.refreshControl {
			if r.isRefreshing && !CloudManager.syncing {
				r.endRefreshing()
			}
			lastSyncUpdate()
		}
	}

	private func lastSyncUpdate() {
		if let r = collection.refreshControl {
			r.attributedTitle = NSAttributedString(string: CloudManager.syncString)
		}
	}

	func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		lastSyncUpdate()
	}

	@IBOutlet private weak var pasteButton: UIBarButtonItem!

	@IBAction private func pasteSelected(_ sender: UIBarButtonItem) {
		addItems(from: UIPasteboard.general.itemProviders)
	}

	@discardableResult
	func addItems(from providers: [NSItemProvider], overrides: ImportOverrides? = nil, skipVisibleErrors: Bool = false) -> PasteResult {
		if providers.count == 0 {
			if !skipVisibleErrors {
				genericAlert(title: "Nothing To Paste", message: "There is currently nothing in the clipboard.")
			}
			return .noData
		}

		if IAPManager.shared.checkInfiniteMode(for: 1) {
			return .tooManyItems
		}

		for item in ArchivedDropItem.importData(providers: providers, delegate: self, overrides: overrides) {

			if Model.isFilteringLabels && !PersistedOptions.dontAutoLabelNewItems {
				item.labels = Model.enabledLabelsForItems
			}

			let destinationIndexPath = IndexPath(item: 0, section: 0)

			collection.performBatchUpdates({
				Model.drops.insert(item, at: 0)
				Model.forceUpdateFilter(signalUpdate: false)
				let itemVisiblyInserted = Model.filteredDrops.contains(item)
				if itemVisiblyInserted {
					collection.insertItems(at: [destinationIndexPath])
					collection.isAccessibilityElement = false
				}
			}, completion: { finished in
				self.collection.scrollToItem(at: destinationIndexPath, at: .centeredVertically, animated: true)
				self.mostRecentIndexPathActioned = destinationIndexPath
				self.focusInitialAccessibilityElement()
			})

			updateEmptyView(animated: true)
		}
		startBgTaskIfNeeded()
		return .success
	}

	@objc private func detailViewClosing() {
		ensureNoEmptySearchResult()
	}

	func sendToTop(item: ArchivedDropItem) {
		guard let i = Model.drops.index(of: item) else { return }
		Model.drops.remove(at: i)
		Model.drops.insert(item, at: 0)
		Model.forceUpdateFilter(signalUpdate: false)
		reloadData()
		Model.save()
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
		if CloudManager.syncSwitchedOn && CloudManager.lastiCloudAccount == nil {
			CloudManager.lastiCloudAccount = FileManager.default.ubiquityIdentityToken
		}
		if Model.legacyMode {
			log("Migrating legacy data store")
			for i in Model.drops {
				i.needsSaving = true
			}
			Model.save()
			Model.legacyMode = false
			log("Migration done")
		}
		Model.searchableIndex(CSSearchableIndex.default(), reindexAllSearchableItemsWithAcknowledgementHandler: {
			let d = UserDefaults.standard
			d.set(currentBuild, forKey: "LastRanVersion")
			d.synchronize()
		})
	}

	private var lowMemoryMode = false {
		didSet {
			for cell in collection.visibleCells as? [ArchivedItemCell] ?? [] {
				cell.lowMemoryMode = lowMemoryMode
				cell.reDecorate()
			}
		}
	}

	override func didReceiveMemoryWarning() {
		if UIApplication.shared.applicationState == .background {
			log("Placing UI in low-memory mode")
			lowMemoryMode = true
		}
		clearCaches()
		super.didReceiveMemoryWarning()
	}

	@objc private func foregrounded() {
		if lowMemoryMode {
			lowMemoryMode = false
		}
		if emptyView != nil {
			blurb(Greetings.randomGreetLine)
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

		let itemCount = Model.filteredDrops.count
		let c = count == 0 ? itemCount : count
		if c > 1 {
			if count > 0 {
				itemsCount.title = "\(c) Selected:"
			} else {
				itemsCount.title = "\(c) Items"
			}
		} else if c == 1 {
			if count > 0 {
				itemsCount.title = "1 Selected:"
			} else {
				itemsCount.title = "1 Item"
			}
		} else {
			itemsCount.title = "No Items"
		}
		itemsCount.isEnabled = itemCount > 0

		let size = count == 0 ? Model.filteredSizeInBytes : Model.sizeForItems(uuids: selectedItems ?? [])
		totalSizeLabel.title = diskSizeFormatter.string(fromByteCount: size)
		deleteButton.isEnabled = count > 0
		editLabelsButton.isEnabled = count > 0

		for item in Model.itemsToReIngest {
			startBgTaskIfNeeded()
			item.reIngest(delegate: self)
		}

		updateLabelIcon()
		currentLabelEditor?.selectedItems = selectedItems
		collection.isAccessibilityElement = Model.filteredDrops.count == 0
	}

	@IBAction private func sortAscendingButtonSelected() {
		let a = UIAlertController(title: "Sort", message: "Please select your preferred order.  This will sort your items once, it will not keep them sorted.", preferredStyle: .actionSheet)
		for sortOption in Model.SortOption.options {
			a.addAction(UIAlertAction(title: sortOption.ascendingTitle, style: .default, handler: sortOption.handlerAscending))
		}
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
		a.popoverPresentationController?.barButtonItem = sortAscendingButton
	}

	@IBAction private func sortDescendingButtonSelected() {
		let a = UIAlertController(title: "Sort", message: "Please select your preferred order. This will sort your items once, it will not keep them sorted.", preferredStyle: .actionSheet)
		for sortOption in Model.SortOption.options {
			a.addAction(UIAlertAction(title: sortOption.descendingTitle, style: .default, handler: sortOption.handlerDescending))
		}
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
		a.popoverPresentationController?.barButtonItem = sortAscendingButton
	}

	@IBAction private func itemsCountSelected(_ sender: UIBarButtonItem) {
		let selectedCount = (selectedItems?.count ?? 0)
		if selectedCount > 0 {
			let a = UIAlertController(title: "Please Confirm", message: nil, preferredStyle: .actionSheet)
			let msg = selectedCount > 1 ? "Deselect \(selectedCount) Items" : "Deselect Item"
			a.addAction(UIAlertAction(title: msg, style: .default, handler: { action in
				if let p = a.popoverPresentationController {
					_ = self.popoverPresentationControllerShouldDismissPopover(p)
				}
				self.selectedItems?.removeAll()
				self.collection.reloadData()
				self.didUpdateItems()
			}))
			a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
			a.modalPresentationStyle = .popover
			navigationController?.visibleViewController?.present(a, animated: true)
			if let p = a.popoverPresentationController {
				p.permittedArrowDirections = [.any]
				p.barButtonItem = itemsCount
				p.delegate = self
			}
		} else {
			let itemCount = Model.filteredDrops.count
			guard itemCount > 0 else { return }
			let a = UIAlertController(title: "Please Confirm", message: nil, preferredStyle: .actionSheet)
			let msg = itemCount > 1 ? "Select \(itemCount) Items" : "Select Item"
			a.addAction(UIAlertAction(title: msg, style: .default, handler: { action in
				if let p = a.popoverPresentationController {
					_ = self.popoverPresentationControllerShouldDismissPopover(p)
				}
				self.selectedItems = Model.filteredDrops.map { $0.uuid }
				self.collection.reloadData()
				self.didUpdateItems()
			}))
			a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
			a.modalPresentationStyle = .popover
			navigationController?.visibleViewController?.present(a, animated: true)
			if let p = a.popoverPresentationController {
				p.permittedArrowDirections = [.any]
				p.barButtonItem = itemsCount
				p.delegate = self
			}
		}
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
		sortAscendingButton.isEnabled = Model.drops.count > 0
		sortDescendingButton.isEnabled = Model.drops.count > 0
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
					e.alpha = PersistedOptions.darkMode ? 0.5 : 1
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
			for cell in collection.visibleCells as? [ArchivedItemCell] ?? [] {
				cell.isEditing = editing
			}
		}
	}

	var itemSize = CGSize.zero
	private func calculateItemSize() {

		func calculateSizes(for columnCount: CGFloat) {
			let layout = (collection.collectionViewLayout as! UICollectionViewFlowLayout)
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
		if let cell = collection.cellForItem(at: indexPath) as? ArchivedItemCell, let b = cell.backgroundView {
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
			collection.refreshControl?.tintColor = view.tintColor
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

		let insets = collection.safeAreaInsets
		let w = insets.left + insets.right
		let h = insets.top + insets.bottom
		let b = collection.bounds.size
		let boundsSize = CGSize(width: b.width - w, height: b.height - h)
		if lastSize == boundsSize { return }
		lastSize = boundsSize

		calculateItemSize()
		DispatchQueue.main.async { [weak self] in
			self?.collection.reloadData()
		}
	}

	/////////////////////////////////

	private var selectedItems: [UUID]?
	@IBAction private func deleteButtonSelected(_ sender: UIBarButtonItem) {
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
			p.barButtonItem = deleteButton
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

	private var firstPresentedAlertController: UIAlertController? {
		return presentedViewController as? UIAlertController
	}

	func dismissAnyPopOver(completion: (()->Void)? = nil) {
		if let p = navigationItem.searchController?.presentedViewController ?? navigationController?.presentedViewController, let pc = p.popoverPresentationController {
			if popoverPresentationControllerShouldDismissPopover(pc) {
				firstPresentedAlertController?.dismiss(animated: true) {
					completion?()
				}
				firstPresentedNavigationController?.viewControllers.first?.dismiss(animated: true) {
					completion?()
				}
				return
			}
		}
		completion?()
	}

	func deleteRequested(for items: [ArchivedDropItem]) {

		let ipsToRemove = Model.delete(items: items)
		if !ipsToRemove.isEmpty {
			collection.performBatchUpdates({
				self.collection.deleteItems(at: ipsToRemove)
			})
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
			blurb(Greetings.randomCleanLine)
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

	func itemIngested(item: ArchivedDropItem) {

		var loadingError = false
		if let (errorPrefix, error) = item.loadingError {
			loadingError = true
			genericAlert(title: "Some data from \(item.displayTitleOrUuid) could not be imported", message: errorPrefix + error.finalDescription)
		}

		item.needsReIngest = false

		if let i = Model.filteredDrops.index(of: item) {
			mostRecentIndexPathActioned = IndexPath(item: i, section: 0)
			collection.reloadItems(at: [mostRecentIndexPathActioned!])
			focusInitialAccessibilityElement()
			item.reIndex()
		} else {
			item.reIndex {
				DispatchQueue.main.async { // if item is still invisible after re-indexing, let the user know
					if !Model.forceUpdateFilter(signalUpdate: true) && !loadingError {
						if item.createdAt == item.updatedAt && !item.loadingAborted {
							genericAlert(title: "Item(s) Added", message: nil, showOK: false)
						}
					}
				}
			}
		}

		if Model.doneIngesting {
			Model.save()
			UIAccessibility.post(notification: .screenChanged, argument: nil)
		} else {
			Model.commitItem(item: item)
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

	func resetSearch(andLabels: Bool) {
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
		if let index = Model.filteredDrops.index(where: { $0.uuid.uuidString == identifier }) {
			dismissAnyPopOver() {
				self.highlightItem(at: index, andOpen: andOpen)
			}
		} else if let index = Model.drops.index(where: { $0.uuid.uuidString == identifier }) {
			dismissAnyPopOver() {
				self.resetSearch(andLabels: true)
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
					self.highlightItem(at: index, andOpen: andOpen)
				}
			}
		}
	}

	private func highlightItem(at index: Int, andOpen: Bool) {
		collection.isUserInteractionEnabled = false
		let ip = IndexPath(item: index, section: 0)
		collection.scrollToItem(at: ip, at: [.centeredVertically, .centeredHorizontally], animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
			if let cell = self.collection.cellForItem(at: ip) as? ArchivedItemCell {
				cell.flash()
				if andOpen {
					self.collectionView(self.collection, didSelectItemAt: ip)
				}
			}
			self.collection.isUserInteractionEnabled = true
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
		collection.performBatchUpdates({
			self.collection.reloadSections(IndexSet(integer: 0))
		})
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

	func noteLastActionedItem(_ item: ArchivedDropItem) {
		if let i = Model.filteredDrops.index(of: item) {
			mostRecentIndexPathActioned = IndexPath(item: i, section: 0)
		}
	}

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
		if let ip = closestIndexPathSinceLast, let cell = collection.cellForItem(at: ip) {
			return cell
		} else {
			return collection
		}
	}

	@objc private func showLabels() {
		performSegue(withIdentifier: "showLabels", sender: nil)
	}

	@objc private func showPreferences() {
		performSegue(withIdentifier: "showPreferences", sender: nil)
	}

	@objc private func openSearch() {
		navigationItem.searchController?.searchBar.becomeFirstResponder()
	}

	@objc private func resetLabels() {
		resetSearch(andLabels: true)
	}

	@objc private func resetSearchTerms() {
		resetSearch(andLabels: false)
	}

	@objc private func toggleEdit() {
		setEditing(!isEditing, animated: true)
	}

	override var keyCommands: [UIKeyCommand]? {
		var a = super.keyCommands ?? []
		a.append(contentsOf: [
			UIKeyCommand(input: "v", modifierFlags: .command, action: #selector(pasteSelected(_:)), discoverabilityTitle: "Paste From Clipboard"),
			UIKeyCommand(input: "l", modifierFlags: .command, action: #selector(showLabels), discoverabilityTitle: "Labels Menu"),
			UIKeyCommand(input: "l", modifierFlags: [.command, .alternate], action: #selector(resetLabels), discoverabilityTitle: "Clear Active Labels"),
			UIKeyCommand(input: ",", modifierFlags: .command, action: #selector(showPreferences), discoverabilityTitle: "Preferences Menu"),
			UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(openSearch), discoverabilityTitle: "Search Items"),
			UIKeyCommand(input: "e", modifierFlags: .command, action: #selector(toggleEdit), discoverabilityTitle: "Toggle Edit Mode")
		])
		return a
	}

	private var searchActive: Bool {
		return navigationItem.searchController?.isActive ?? false
	}

	func showIAPPrompt(title: String, subtitle: String,
					   actionTitle: String? = nil, actionAction: (()->Void)? = nil,
					   destructiveTitle: String? = nil, destructiveAction: (()->Void)? = nil,
					   cancelTitle: String? = nil) {

		ViewController.shared.dismissAnyPopOver()

		if searchActive || Model.isFiltering {
			ViewController.shared.resetSearch(andLabels: true)
		}

		let a = UIAlertController(title: title, message: subtitle, preferredStyle: .alert)
		if let destructiveTitle = destructiveTitle {
			a.addAction(UIAlertAction(title: destructiveTitle, style: .destructive, handler: { _ in destructiveAction?() }))
		}
		if let actionTitle = actionTitle {
			a.addAction(UIAlertAction(title: actionTitle, style: .default, handler: { _ in actionAction?() }))
		}
		if let cancelTitle = cancelTitle {
			a.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
		}

		present(a, animated: true)
	}
}

final class ShowDetailSegue: UIStoryboardSegue {
	override func perform() {
		(source.presentedViewController ?? source).present(destination, animated: true)
	}
}
