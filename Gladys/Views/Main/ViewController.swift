
import UIKit
import CoreSpotlight
import GladysFramework
import Intents

enum PasteResult {
	case success, noData, tooManyItems
}

@discardableResult
func genericAlert(title: String?, message: String?, autoDismiss: Bool = true, buttonTitle: String? = "OK", completion: (()->Void)? = nil) -> UIAlertController {
	let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
	if let buttonTitle = buttonTitle {
		a.addAction(UIAlertAction(title: buttonTitle, style: .default) { _ in completion?() })
	}

	ViewController.top.present(a, animated: true)

	if buttonTitle == nil && autoDismiss {
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
	a.addAction(UIAlertAction(title: action, style: .default) { ac in
		let result = a.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		completion(result)
	})
	a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { ac in
		completion(nil)
	})
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
	@IBOutlet private weak var shareButton: UIBarButtonItem!

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

	private var registeredForBackground = false
	private func startBgTaskIfNeeded() {
		if !registeredForBackground {
			registeredForBackground = true
			BackgroundTask.registerForBackground()
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
			if session.localDragSession?.localContext as? String != "typeItem" {
				showDragModeOverlay(true)
			}
		}
	}

	func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
		showDragModeOverlay(false)

		guard let droppedIds = ArchivedDropItemType.droppedIds else { return }

		let items = droppedIds.compactMap { Model.item(uuid: $0) }
		if items.count > 0 {
			if dragModeMove {
				deleteRequested(for: items)
			} else {
				items.forEach { $0.donateCopyIntent() }
			}
		}
		ArchivedDropItemType.droppedIds = nil
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
		let type = PersistedOptions.wideMode ? "WideArchivedItemCell" : "ArchivedItemCell"
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: type, for: indexPath) as! ArchivedItemCell
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

	func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {}

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
					let sourceIndex = Model.drops.firstIndex(of: existingItem),
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

				startBgTaskIfNeeded()
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
						if itemVisiblyInserted {
							self.mostRecentIndexPathActioned = destinationIndexPath
						}
						self.focusInitialAccessibilityElement()
					})

					if itemVisiblyInserted {
						firstDestinationPath = destinationIndexPath
					}
				}
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
	}

	func resetForDragEntry(session: UIDropSession) {
		if currentPreferencesView != nil && !session.hasItemsConforming(toTypeIdentifiers: [GladysFileUTI, "public.zip-archive"]) {
			dismissAnyPopOver()
		} else if (componentDropActiveFromDetailView == nil && currentDetailView != nil) || currentLabelSelector != nil {
			dismissAnyPopOver()
		}
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {

		if let context = session.localDragSession?.localContext as? String, context == "typeItem", destinationIndexPath == nil { // create standalone data component
			return UICollectionViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
		}

		// normal insert
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
			popoverPresentationController.presentingViewController.view.cover(with: d)
			popoverPresentationController.passthroughViews = [d]
			dimView = d
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
				let cell = collection.cellForItem(at: indexPath),
				let myNavView = navigationController?.view
				else { return }

			d.item = item

			let c = patternColor
			n.view.backgroundColor = c

			let cellRect = cell.convert(cell.bounds.insetBy(dx: 6, dy: 6), to: myNavView)
			p.permittedArrowDirections = PersistedOptions.wideMode ? [.left, .right] : [.down, .left, .right]
			p.sourceView = navigationController!.view
			p.sourceRect = cellRect
			p.backgroundColor = c
			p.delegate = self

			if componentDropActiveFromDetailView != nil {
				trackCellForAWhile(cell, for: p, in: myNavView)
			}

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

	private func trackCellForAWhile(_ cell: UICollectionViewCell, for popOver: UIPopoverPresentationController, in container: UIView) {
		var observation: NSKeyValueObservation?
		observation = cell.observe(\.center, options: NSKeyValueObservingOptions.new) { strongCell, change in
			let cellRect = strongCell.convert(cell.bounds.insetBy(dx: 6, dy: 6), to: container)
			popOver.sourceRect = cellRect
			popOver.containerView?.setNeedsLayout()
			UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut, animations: {
				popOver.containerView?.layoutIfNeeded()
			}, completion: nil)
			observation = nil
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
			if observation != nil { // keep it around
				observation = nil
			}
		}
	}

	var componentDropActiveFromDetailView: DetailController?

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

		if collectionView.hasActiveDrop && componentDropActiveFromDetailView == nil { return }

		let item = Model.filteredDrops[indexPath.item]
		if item.shouldDisplayLoading {
			return
		}

		if isEditing {
			let selectedIndex = selectedItems?.firstIndex { $0 == item.uuid }
			if let selectedIndex = selectedIndex {
				selectedItems?.remove(at: selectedIndex)
			} else {
				selectedItems?.append(item.uuid)
			}
			didUpdateItems()
			if let cell = collectionView.cellForItem(at: indexPath) as? ArchivedItemCell {
				cell.isSelectedForAction = (selectedIndex == nil)
			}

		} else if item.needsUnlock {
			mostRecentIndexPathActioned = indexPath
			item.unlock(from: ViewController.top, label: "Unlock Item", action: "Unlock") { success in
				if success {
					item.needsUnlock = false
                    item.postModified()
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
		settingsButton.accessibilityLabel = "Settings"
		shareButton.accessibilityLabel = "Share"

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

		lastSyncUpdate()

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

		Model.checkForUpgrade()

		didUpdateItems()
		updateEmptyView(animated: false)
		emptyView?.alpha = PersistedOptions.darkMode ? 0.5 : 1
		blurb("Ready! Drop me stuff.")

		cloudStatusChanged()
		if !PersistedOptions.pasteShortcutAutoDonated {
			donatePasteIntent()
		}
	}

	deinit {
		Model.doneMonitoringChanges()
	}

	@available(iOS 12.0, *)
	var pasteIntent: PasteClipboardIntent {
		let intent = PasteClipboardIntent()
		intent.suggestedInvocationPhrase = "Paste in Gladys"
		return intent
	}

	func donatePasteIntent() {
		if #available(iOS 12.0, *) {
			let interaction = INInteraction(intent: pasteIntent, response: nil)
			interaction.identifier = "paste-in-gladys"
			interaction.donate { error in
				if let error = error {
					log("Error donating paste shortcut: \(error.localizedDescription)")
				} else {
					log("Donated paste shortcut")
					PersistedOptions.pasteShortcutAutoDonated = true
				}
			}
		}
	}

	private var acceptAlert: UIAlertController?

	@objc private func acceptStarted() {
		acceptAlert = genericAlert(title: "Accepting Share...", message: nil, autoDismiss: false, buttonTitle: nil, completion: nil)
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
			if PersistedOptions.darkMode {
				r.attributedTitle = NSAttributedString(string: CloudManager.syncString, attributes: [.font: UIFont.preferredFont(forTextStyle: .caption2), .foregroundColor: UIColor.lightGray])
			} else {
				r.attributedTitle = NSAttributedString(string: CloudManager.syncString, attributes: [.font: UIFont.preferredFont(forTextStyle: .caption2), .foregroundColor: UIColor.darkGray])
			}
		}
	}

	func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		lastSyncUpdate()
	}

	@IBOutlet private weak var pasteButton: UIBarButtonItem!

	@IBAction private func pasteSelected(_ sender: UIBarButtonItem) {
		donatePasteIntent()
		pasteItems(from: UIPasteboard.general.itemProviders, overrides: nil, skipVisibleErrors: false)
	}

	@discardableResult
	func pasteItems(from providers: [NSItemProvider], overrides: ImportOverrides?, skipVisibleErrors: Bool) -> PasteResult {
		
		if providers.count == 0 {
			if !skipVisibleErrors {
				genericAlert(title: "Nothing To Paste", message: "There is currently nothing in the clipboard.")
			}
			return .noData
		}

		if IAPManager.shared.checkInfiniteMode(for: 1) {
			return .tooManyItems
		}

		for provider in providers { // separate item for each provider in the pasteboard
			for item in ArchivedDropItem.importData(providers: [provider], delegate: self, overrides: overrides) {

				if Model.isFilteringLabels && !PersistedOptions.dontAutoLabelNewItems {
					item.labels = Model.enabledLabelsForItems
				}

				let destinationIndexPath = IndexPath(item: 0, section: 0)

				var itemVisiblyInserted = false
				collection.performBatchUpdates({
					Model.drops.insert(item, at: 0)
					Model.forceUpdateFilter(signalUpdate: false)
					itemVisiblyInserted = Model.filteredDrops.contains(item)
					if itemVisiblyInserted {
						collection.insertItems(at: [destinationIndexPath])
						collection.isAccessibilityElement = false
					}
				}, completion: { finished in
					if itemVisiblyInserted {
						self.collection.scrollToItem(at: destinationIndexPath, at: .centeredVertically, animated: true)
						self.mostRecentIndexPathActioned = destinationIndexPath
					}
					self.focusInitialAccessibilityElement()
				})

				updateEmptyView(animated: true)
			}
		}

		startBgTaskIfNeeded()
		return .success
	}

	@objc private func detailViewClosing() {
		ensureNoEmptySearchResult()
	}

	func sendToTop(item: ArchivedDropItem) {
		guard let i = Model.drops.firstIndex(of: item) else { return }
		Model.drops.remove(at: i)
		Model.drops.insert(item, at: 0)
		Model.forceUpdateFilter(signalUpdate: false)
		reloadData()
		Model.saveIndexOnly()
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

	private func setItemCountTitle(_ count: Int, _ text: String, colon: Bool) {
		let colonText = colon && collection.bounds.width > 512 ? ":" : ""
		itemsCount.title = "\(count) \(text)\(colonText)"
	}

	private var emptyView: UIImageView?
	@objc private func didUpdateItems() {
		editButtonItem.isEnabled = Model.drops.count > 0

		selectedItems = selectedItems?.filter { uuid in Model.drops.contains(where: { $0.uuid == uuid }) }

		let selectedCount = selectedItems?.count ?? 0
		let someSelected = selectedCount > 0

		let itemCount = Model.filteredDrops.count
		let c = someSelected ? selectedCount : itemCount
		if c > 1 {
			if someSelected {
				setItemCountTitle(c, "Selected", colon: true)
			} else {
				setItemCountTitle(c, "Items", colon: false)
			}
		} else if c == 1 {
			if someSelected {
				setItemCountTitle(1, "Selected", colon: true)
			} else {
				setItemCountTitle(1, "Item", colon: false)
			}
		} else {
			itemsCount.title = "No Items"
		}
		itemsCount.isEnabled = itemCount > 0

		let size = someSelected ? Model.sizeForItems(uuids: selectedItems ?? []) : Model.filteredSizeInBytes
		totalSizeLabel.title = diskSizeFormatter.string(fromByteCount: size)
		deleteButton.isEnabled = someSelected
		editLabelsButton.isEnabled = someSelected
		shareButton.isEnabled = someSelected

		let itemsToReIngest = Model.itemsToReIngest
		if itemsToReIngest.count > 0 {
			startBgTaskIfNeeded()
			itemsToReIngest.forEach { $0.reIngest(delegate: self) }
		}

		updateLabelIcon()
		currentLabelEditor?.selectedItems = selectedItems
		collection.isAccessibilityElement = Model.filteredDrops.isEmpty
	}

	@IBAction func shareButtonSelected(_ sender: UIBarButtonItem) {
		guard let selectedItems = selectedItems else { return }
		let providers = selectedItems.compactMap { Model.item(uuid: $0)?.itemProviderForSharing }
		if providers.isEmpty { return }
		let a = UIActivityViewController(activityItems: providers, applicationActivities: nil)
		a.completionWithItemsHandler = { [weak self] _, done, _, _ in
			if done {
				self?.setEditing(false, animated: true)
			}
		}
		a.popoverPresentationController?.barButtonItem = sender
		present(a, animated: true)
	}

	@IBAction private func sortAscendingButtonSelected() {
		let a = UIAlertController(title: "Sort", message: "Please select your preferred order.  This will sort your items once, it will not keep them sorted.", preferredStyle: .actionSheet)
		for sortOption in Model.SortOption.options {
			a.addAction(UIAlertAction(title: sortOption.ascendingTitle, style: .default) { _ in
				self.sortRequested(sortOption, ascending: true, button: self.sortDescendingButton)
			})
		}
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
		a.popoverPresentationController?.barButtonItem = sortAscendingButton
	}

	@IBAction private func sortDescendingButtonSelected() {
		let a = UIAlertController(title: "Sort", message: "Please select your preferred order. This will sort your items once, it will not keep them sorted.", preferredStyle: .actionSheet)
		for sortOption in Model.SortOption.options {
			a.addAction(UIAlertAction(title: sortOption.descendingTitle, style: .default) { _ in
				self.sortRequested(sortOption, ascending: false, button: self.sortAscendingButton)
			})
		}
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
		a.popoverPresentationController?.barButtonItem = sortAscendingButton
	}

	private func sortRequested(_ option: Model.SortOption, ascending: Bool, verifyRange: Bool = true, ignoreSelectedItems: Bool = false, button: UIBarButtonItem) {
		let items = ignoreSelectedItems ? [] : (selectedItems?.compactMap { Model.item(uuid: $0) } ?? [])
		if !items.isEmpty && verifyRange {
			let a = UIAlertController(title: "Sort selected items?", message: "You have selected a range of items. Would you like to sort just the selected items, or sort all the items in your collection?", preferredStyle: .actionSheet)
			a.addAction(UIAlertAction(title: "Sort Selected", style: .default) { _ in
				self.sortRequested(option, ascending: ascending, verifyRange: false, ignoreSelectedItems: false, button: button)
			})
			a.addAction(UIAlertAction(title: "Sort All", style: .destructive) { _ in
				self.sortRequested(option, ascending: ascending, verifyRange: false, ignoreSelectedItems: true, button: button)
			})
			a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
			present(a, animated: true)
			a.popoverPresentationController?.barButtonItem = button
		} else {
			let sortMethod = option.handlerForSort(itemsToSort: items, ascending: ascending)
			sortMethod()
			Model.forceUpdateFilter(signalUpdate: false)
			reloadData()
			Model.save()
		}
	}

	@IBAction private func itemsCountSelected(_ sender: UIBarButtonItem) {
		let selectedCount = (selectedItems?.count ?? 0)
		if selectedCount > 0 {
			let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
			let msg = selectedCount > 1 ? "Deselect \(selectedCount) Items" : "Deselect Item"
			a.addAction(UIAlertAction(title: msg, style: .default) { action in
				if let p = a.popoverPresentationController {
					_ = self.popoverPresentationControllerShouldDismissPopover(p)
				}
				self.selectedItems?.removeAll()
				self.collection.reloadData()
				self.didUpdateItems()
			})
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
			let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
			let msg = itemCount > 1 ? "Select \(itemCount) Items" : "Select Item"
			a.addAction(UIAlertAction(title: msg, style: .default) { action in
				if let p = a.popoverPresentationController {
					_ = self.popoverPresentationControllerShouldDismissPopover(p)
				}
				self.selectedItems = Model.filteredDrops.map { $0.uuid }
				self.collection.reloadData()
				self.didUpdateItems()
			})
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

		func calculateWideSizes(for columnCount: CGFloat) {
			let layout = (collection.collectionViewLayout as! UICollectionViewFlowLayout)
			let extras = (layout.minimumInteritemSpacing * (columnCount - 1.0)) + layout.sectionInset.left + layout.sectionInset.right
			let side = ((lastSize.width - extras) / columnCount).rounded(.down)
			itemSize = CGSize(width: side, height: 80)
		}

		if PersistedOptions.wideMode {
			if lastSize.width >= 768 {
				calculateWideSizes(for: 2)
			} else {
				itemSize = CGSize(width: lastSize.width - 20, height: 80)
			}
		} else {
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

		let font: UIFont
		let b = collection.bounds.size
		if b.width > 375 {
			font = UIFont.preferredFont(forTextStyle: .body)
		} else if b.width > 320 {
			let bodyFont = UIFont.preferredFont(forTextStyle: .body)
			font = bodyFont.withSize(bodyFont.pointSize - 2)
		} else {
			font = UIFont.preferredFont(forTextStyle: .caption1)
		}
		itemsCount.setTitleTextAttributes([.font: font], for: .normal)
		totalSizeLabel.setTitleTextAttributes([.font: font], for: .normal)

		let insets = collection.safeAreaInsets
		let w = insets.left + insets.right
		let h = insets.top + insets.bottom
		let boundsSize = CGSize(width: b.width - w, height: b.height - h)
		if lastSize == boundsSize { return }
		lastSize = boundsSize

		calculateItemSize()

		shareButton.width = shareButton.image!.size.width + 22
		editLabelsButton.width = editLabelsButton.image!.size.width + 22
		deleteButton.width = deleteButton.image!.size.width + 22
		sortAscendingButton.width = sortAscendingButton.image!.size.width + 22
		sortDescendingButton.width = sortDescendingButton.image!.size.width + 22

		DispatchQueue.main.async { [weak self] in
			guard let s = self else { return }
			s.collection.reloadData()
			if s.isEditing {
				s.didUpdateItems()
			}
		}
	}

	/////////////////////////////////

	private var selectedItems: [UUID]?
	@IBAction private func deleteButtonSelected(_ sender: UIBarButtonItem) {
		guard let candidates = selectedItems, candidates.count > 0 else { return }

		let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		let msg = candidates.count > 1 ? "Delete \(candidates.count) Items" : "Delete Item"
		a.addAction(UIAlertAction(title: msg, style: .destructive) { action in
			if let p = a.popoverPresentationController {
				_ = self.popoverPresentationControllerShouldDismissPopover(p)
			}
			self.proceedWithDelete()
		})
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
		let v = navigationController?.presentedViewController ??  presentedViewController?.presentedViewController?.presentedViewController ?? presentedViewController?.presentedViewController ?? presentedViewController
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
		return (navigationController?.presentedViewController ?? presentedViewController) as? UIAlertController
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

	func dismissAnyPopOverOrModal(completion: (()->Void)? = nil) {
		dismissAnyPopOver() {
			if let p = self.navigationItem.searchController?.presentedViewController ?? self.navigationController?.presentedViewController {
				p.dismiss(animated: true) {
					completion?()
				}
			} else {
				completion?()
			}
		}
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

		if let i = Model.filteredDrops.firstIndex(of: item) {
			mostRecentIndexPathActioned = IndexPath(item: i, section: 0)
			if currentDetailView == nil {
				focusInitialAccessibilityElement()
			}
			item.reIndex()
		} else {
			item.reIndex {
				DispatchQueue.main.async { // if item is still invisible after re-indexing, let the user know
					if !Model.forceUpdateFilter(signalUpdate: true) && !loadingError {
						if item.createdAt == item.updatedAt && !item.loadingAborted {
							genericAlert(title: "Item(s) Added", message: nil, buttonTitle: nil)
						}
					}
				}
			}
		}

		if Model.doneIngesting {
			Model.save()
			UIAccessibility.post(notification: .screenChanged, argument: nil)

			if registeredForBackground {
				registeredForBackground = false
				BackgroundTask.unregisterForBackground()
			}

		} else {
			Model.commitItem(item: item)
		}
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

	func highlightItem(with identifier: String, andOpen: Bool = false, andPreview: Bool = false, focusOnChild childUuid: String? = nil) {
		if let index = Model.filteredDrops.firstIndex(where: { $0.uuid.uuidString == identifier }) {
			dismissAnyPopOverOrModal() {
				self.highlightItem(at: index, andOpen: andOpen, andPreview: andPreview, focusOnChild: childUuid)
			}
		} else if let index = Model.drops.firstIndex(where: { $0.uuid.uuidString == identifier }) {
			dismissAnyPopOverOrModal() {
				self.resetSearch(andLabels: true)
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
					self.highlightItem(at: index, andOpen: andOpen, andPreview: andPreview, focusOnChild: childUuid)
				}
			}
		}
	}

	private func highlightItem(at index: Int, andOpen: Bool, andPreview: Bool, focusOnChild childUuid: String?) {
		collection.isUserInteractionEnabled = false
		let ip = IndexPath(item: index, section: 0)
		collection.scrollToItem(at: ip, at: [.centeredVertically, .centeredHorizontally], animated: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
			if let cell = self.collection.cellForItem(at: ip) as? ArchivedItemCell {
				cell.flash()
				if andOpen {
					self.collectionView(self.collection, didSelectItemAt: ip)
				} else if andPreview {
					let item = Model.filteredDrops[index]
					item.tryPreview(in: ViewController.top, from: cell, preferChild: childUuid)
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

	@objc func reloadData(onlyIfPopulated: Bool = false) {
		updateLabelIcon()
		if onlyIfPopulated && Model.filteredDrops.filter({ !$0.isBeingCreatedBySync }).isEmpty {
			return
		}
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
		if let i = Model.filteredDrops.firstIndex(of: item) {
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
			a.addAction(UIAlertAction(title: destructiveTitle, style: .destructive) { _ in destructiveAction?() })
		}
		if let actionTitle = actionTitle {
			a.addAction(UIAlertAction(title: actionTitle, style: .default) { _ in actionAction?() })
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
