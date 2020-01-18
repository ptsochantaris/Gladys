
import UIKit
import GladysFramework
import Intents

extension UIKeyCommand {
    static func makeCommand(input: String, modifierFlags: UIKeyModifierFlags, action: Selector, title: String) -> UIKeyCommand {
        let c = UIKeyCommand(input: input, modifierFlags: modifierFlags, action: action)
        c.title = title
        return c
    }
}

var currentWindow: UIWindow? {
    return UIApplication.shared.connectedScenes.filter({ $0.activationState != .background }).compactMap({ ($0 as? UIWindowScene)?.windows.first }).lazy.first
}

@discardableResult
func genericAlert(title: String?, message: String?, autoDismiss: Bool = true, buttonTitle: String? = "OK", completion: (()->Void)? = nil) -> UIAlertController {
        
	let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
	if let buttonTitle = buttonTitle {
		a.addAction(UIAlertAction(title: buttonTitle, style: .default) { _ in completion?() })
	}

    if let connectedWindow = currentWindow {
        connectedWindow.alertPresenter?.present(a, animated: true)
    }
    
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

final class ViewController: GladysViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching,
	UISearchControllerDelegate, UISearchResultsUpdating, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource,
    UICollectionViewDropDelegate, UICollectionViewDragDelegate, UIPopoverPresentationControllerDelegate,
    UICloudSharingControllerDelegate {

	@IBOutlet private weak var collection: UICollectionView!
	@IBOutlet private weak var totalSizeLabel: UIBarButtonItem!
	@IBOutlet private weak var deleteButton: UIBarButtonItem!
	@IBOutlet private weak var editLabelsButton: UIBarButtonItem!
	@IBOutlet private weak var sortAscendingButton: UIBarButtonItem!
	@IBOutlet private weak var labelsButton: UIBarButtonItem!
	@IBOutlet private weak var settingsButton: UIBarButtonItem!
	@IBOutlet private weak var itemsCount: UIBarButtonItem!
	@IBOutlet private weak var dragModePanel: UIView!
	@IBOutlet private weak var dragModeButton: UIButton!
	@IBOutlet private weak var dragModeTitle: UILabel!
	@IBOutlet private weak var shareButton: UIBarButtonItem!
    @IBOutlet private weak var editButton: UIBarButtonItem!

    var filter: ModelFilterContext!
    
	var itemView: UICollectionView {
		return collection!
	}

	/////////////////////////////

	private var dragModeReverse = false

	private func showDragModeOverlay(_ show: Bool) {
		if dragModePanel.superview != nil, !show {
			UIView.animate(withDuration: 0.1, animations: {
				self.dragModePanel.alpha = 0
			}, completion: { finished in
				self.dragModePanel.removeFromSuperview()
			})
		} else if dragModePanel.superview == nil, show, let n = navigationController {
			dragModeReverse = false
			updateDragModeOverlay()
            n.view.addSubview(dragModePanel)
			NSLayoutConstraint.activate([
				dragModePanel.centerXAnchor.constraint(equalTo: collection.centerXAnchor),
                dragModePanel.topAnchor.constraint(equalTo: n.view.topAnchor)
				])
			UIView.animate(withDuration: 0.1, animations: {
				self.dragModePanel.alpha = 1
			}, completion: nil)
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
        
        Component.droppedIds.removeAll()
	}
    
	func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
		showDragModeOverlay(false)
        
		let items = Component.droppedIds.compactMap { Model.item(uuid: $0) }
		if !items.isEmpty {
			if dragModeMove {
				Model.delete(items: items)
			} else {
				items.forEach { $0.donateCopyIntent() }
			}
		}
        
        Component.droppedIds.removeAll()
	}

	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        Component.droppedIds.removeAll()
		let item = filter.filteredDrops[indexPath.item]
        if item.flags.contains(.needsUnlock) { return [] }
		return [item.dragItem]
	}

	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		let item = filter.filteredDrops[indexPath.item]
		let dragItem = item.dragItem
        if session.localContext as? String == "typeItem" || session.items.contains(dragItem) || item.flags.contains(.needsUnlock) {
			return []
		} else {
			return [dragItem]
		}
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return filter.filteredDrops.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let type = PersistedOptions.wideMode ? "WideArchivedItemCell" : "ArchivedItemCell"
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: type, for: indexPath) as! ArchivedItemCell
		if indexPath.item < filter.filteredDrops.count {
			cell.lowMemoryMode = lowMemoryMode
			let item = filter.filteredDrops[indexPath.item]
			cell.archivedDropItem = item
			cell.isEditing = isEditing
			cell.isSelectedForAction = selectedItems?.contains(item.uuid) ?? false
		}
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
		for indexPath in indexPaths {
			ArchivedItemCell.warmUp(for: filter.filteredDrops[indexPath.item])
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
                
        coordinator.session.progressIndicatorStyle = .none
        
        var needsPost = false
        var needsSaveIndex = false
        var needsFullSave = false
                
        let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: filter.filteredDrops.count, section: 0)
        
        let dropItems = coordinator.items.map( { $0.dragItem })
        
        for dragItem in dropItems {
            
            if let existingItem = dragItem.localObject as? ArchivedItem {
                
                Component.droppedIds.remove(existingItem.uuid) // do not count this as an external drop
                
                if let modelSourceIndex = Model.drops.firstIndex(of: existingItem) {
                    let itemToMove = Model.drops.remove(at: modelSourceIndex)
                    Model.drops.insert(itemToMove, at: destinationIndexPath.item)
                    needsSaveIndex = true
                }
                
            } else {
                
                for item in ArchivedItem.importData(providers: [dragItem.itemProvider], overrides: nil) {
                    var dataIndex = coordinator.destinationIndexPath?.item ?? filter.filteredDrops.count
                    
                    if filter.isFiltering {
                        dataIndex = filter.nearestUnfilteredIndexForFilteredIndex(dataIndex)
                        if filter.isFilteringLabels && !PersistedOptions.dontAutoLabelNewItems {
                            item.labels = filter.enabledLabelsForItems
                        }
                    }
                    
                    Model.drops.insert(item, at: dataIndex)
                    needsFullSave = true
                    needsPost = true
                }
            }
        }
        
        if needsPost {
            self.focusInitialAccessibilityElement()
            self.updateEmptyView(animated: true)
        }
        
        if needsFullSave {
            Model.save()
        } else if needsSaveIndex {
            Model.saveIndexOnly()
        }
        
        for dragItem in dropItems {
            coordinator.drop(dragItem, toItemAt: destinationIndexPath)
        }

        self.collection.isAccessibilityElement = false
        self.mostRecentIndexPathActioned = destinationIndexPath
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
        let operation: UIDropOperation = countInserts(in: session) > 0 ? .copy : .move
		return UICollectionViewDropProposal(operation: operation, intent: .insertAtDestinationIndexPath)
	}
    
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

		case "showDetail":
			guard let item = sender as? ArchivedItem,
				let indexPath = mostRecentIndexPathActioned,
				let n = segue.destination as? UINavigationController,
				let d = n.topViewController as? DetailController,
				let p = n.popoverPresentationController,
				let cell = collection.cellForItem(at: indexPath),
				let myNavView = navigationController?.view
				else { return }

			d.item = item

            p.popoverBackgroundViewClass = GladysPopoverBackgroundView.self
			p.permittedArrowDirections = PersistedOptions.wideMode ? [.left, .right] : [.any]
			p.sourceView = navigationController!.view
            p.sourceRect = cell.convert(cell.bounds.insetBy(dx: cell.bounds.width * 0.3, dy: cell.bounds.height * 0.3), to: myNavView)
			p.delegate = self

			if componentDropActiveFromDetailView != nil {
				trackCellForAWhile(cell, for: p, in: myNavView)
			}

		case "showLabels":
			guard let n = segue.destination as? UINavigationController,
				let p = n.popoverPresentationController
				else { return }

			p.delegate = self
			if isEditing {
				setEditing(false, animated: true)
			}
            (n.viewControllers.first as? LabelSelector)?.filter = filter

		case "showLabelEditor":
			guard let n = segue.destination as? UINavigationController,
				let e = n.topViewController as? LabelEditorController,
				let p = n.popoverPresentationController
				else { return }

			p.delegate = self
            e.currentFilter = filter
			e.selectedItems = selectedItems
			e.endCallback = { [weak self] hasChanges in
				if hasChanges {
					self?.setEditing(false, animated: true)
				}
			}
            
        case "toSiriShortcuts":
            guard let d = segue.destination as? SiriShortcutsViewController,
                let cell = sender as? ArchivedItemCell,
                let item = cell.archivedDropItem
                else { return }
            
            d.sourceItem = item
            if let p = d.popoverPresentationController {
                p.sourceView = cell
                p.delegate = self
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

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

		if collectionView.hasActiveDrop && componentDropActiveFromDetailView == nil { return }

		let item = filter.filteredDrops[indexPath.item]
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
			updateUI()
			if let cell = collectionView.cellForItem(at: indexPath) as? ArchivedItemCell {
				cell.isSelectedForAction = (selectedIndex == nil)
			}

		} else if item.flags.contains(.needsUnlock) {
			mostRecentIndexPathActioned = indexPath
            item.unlock(label: "Unlock Item", action: "Unlock") { success in
                if success {
                    item.flags.remove(.needsUnlock)
                    item.postModified()
                }
            }
            
		} else {
			mostRecentIndexPathActioned = indexPath

			switch PersistedOptions.actionOnTap {

			case .infoPanel:
				performSegue(withIdentifier: "showDetail", sender: item)

			case .copy:
				item.copyToPasteboard()
				genericAlert(title: nil, message: "Copied to clipboard", buttonTitle: nil)

			case .open:
				item.tryOpen(in: nil) { [weak self] success in
					if !success {
						self?.performSegue(withIdentifier: "showDetail", sender: item)
					}
				}

			case .preview:
				let cell = collectionView.cellForItem(at: indexPath) as? ArchivedItemCell
                if let presenter = view.window?.alertPresenter, !item.tryPreview(in: presenter, from: cell) {
                    performSegue(withIdentifier: "showDetail", sender: item)
                }
            case .none:
                break
			}
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		navigationItem.largeTitleDisplayMode = .never
		navigationItem.largeTitleDisplayMode = .automatic
		pasteButton.accessibilityLabel = "Paste from clipboard"
		settingsButton.accessibilityLabel = "Settings"
		shareButton.accessibilityLabel = "Share"

        pasteButton.image = UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(weight: .light))
        
		dragModePanel.translatesAutoresizingMaskIntoConstraints = false
        dragModePanel.layer.shadowColor = UIColor.label.cgColor
		dragModePanel.layer.shadowOffset = CGSize(width: 0, height: 0)
		dragModePanel.layer.shadowOpacity = 0.3
		dragModePanel.layer.shadowRadius = 1
		dragModePanel.layer.cornerRadius = 100
		dragModePanel.alpha = 0
	}
    
    var onLoad: ((ViewController)->Void)?

	override func viewDidLoad() {
		super.viewDidLoad()
        
        collection.reorderingCadence = .slow
		collection.accessibilityLabel = "Items"
		collection.dragInteractionEnabled = true

		navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor(named: "colorLightGray")!
		]
		navigationController?.navigationBar.largeTitleTextAttributes = [
			.foregroundColor: UIColor(named: "colorLightGray")!
		]

		let searchController = UISearchController(searchResultsController: nil)
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.delegate = self
		searchController.searchResultsUpdater = self
		navigationItem.searchController = searchController

		searchTimer = PopTimer(timeInterval: 0.4) { [weak searchController, weak self] in
            self?.filter.filter = searchController?.searchBar.text
			self?.updateUI()
		}

		navigationController?.setToolbarHidden(true, animated: false)

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(labelSelectionChanged), name: .LabelSelectionChanged, object: nil)
        n.addObserver(self, selector: #selector(reloadDataRequested(_:)), name: .ItemCollectionNeedsDisplay, object: nil)
		n.addObserver(self, selector: #selector(modelDataUpdate(_:)), name: .ModelDataUpdated, object: nil)
        n.addObserver(self, selector: #selector(itemCreated(_:)), name: .ItemAddedBySync, object: nil)
		n.addObserver(self, selector: #selector(cloudStatusChanged), name: .CloudManagerStatusChanged, object: nil)
		n.addObserver(self, selector: #selector(reachabilityChanged), name: .ReachabilityChanged, object: nil)
		n.addObserver(self, selector: #selector(acceptStarted), name: .AcceptStarting, object: nil)
		n.addObserver(self, selector: #selector(acceptEnded), name: .AcceptEnding, object: nil)
        n.addObserver(self, selector: #selector(foregrounded), name: UIApplication.willEnterForegroundNotification, object: nil)
        n.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
        n.addObserver(self, selector: #selector(forceLayout), name: .ForceLayoutRequested, object: nil)
        n.addObserver(self, selector: #selector(itemIngested(_:)), name: .IngestComplete, object: nil)
        n.addObserver(self, selector: #selector(highlightItem(_:)), name: .HighlightItemRequested, object: nil)
        n.addObserver(self, selector: #selector(uiRequest(_:)), name: .UIRequest, object: nil)
        n.addObserver(self, selector: #selector(dismissAnyPopoverRequested), name: .DismissPopoversRequest, object: nil)
        n.addObserver(self, selector: #selector(resetSearchRequest), name: .ResetSearchRequest, object: nil)
        n.addObserver(self, selector: #selector(startSearch(_:)), name: .StartSearchRequest, object: nil)
        n.addObserver(self, selector: #selector(forcePaste), name: .ForcePasteRequest, object: nil)
        
        if filter.isFilteringLabels { // in case we're restored with active labels
            filter.updateFilter(signalUpdate: false)
        }

        updateUI()
		emptyView?.alpha = 1
        blurb(Greetings.openLine)

		cloudStatusChanged()
        
        dismissOnNewWindow = false
        autoConfigureButtons = true
        
        userActivity = NSUserActivity(activityType: kGladysMainListActivity)
        userActivity?.needsSave = true
	}
        
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let o = onLoad {
            o(self)
            onLoad = nil
        }
    }

    @objc private func resetSearchRequest() {
        if searchActive || filter.isFiltering {
            resetSearch(andLabels: true)
        }
    }
        
    @objc private func uiRequest(_ notification: Notification) {
        guard let request = notification.object as? UIRequest else { return }
        if request.sourceScene != view.window?.windowScene {
            return
        }

        if request.pushInsteadOfPresent {
            navigationController?.pushViewController(request.vc, animated: true)
        } else {
            present(request.vc, animated: true)
            if let p = request.vc.popoverPresentationController {
                p.sourceView = request.sourceView
                p.sourceRect = request.sourceRect ?? .zero
                p.barButtonItem = request.sourceButton
            }
        }
    }
    
	deinit {
        log("Main VC deinitialised")
	}

	private var acceptAlert: UIAlertController?

	@objc private func acceptStarted() {
		acceptAlert = genericAlert(title: "Accepting Share…", message: nil, autoDismiss: false, buttonTitle: nil, completion: nil)
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
            r.attributedTitle = NSAttributedString(string: CloudManager.syncString, attributes: [:])
		}
	}

	func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		lastSyncUpdate()
	}

	@IBOutlet private weak var pasteButton: UIBarButtonItem!

	@IBAction private func pasteSelected(_ sender: UIBarButtonItem) {
        Model.donatePasteIntent()
        if Model.pasteItems(from: UIPasteboard.general.itemProviders, overrides: nil) == .noData {
            genericAlert(title: "Nothing to Paste", message: "There is currently nothing in the clipboard.")
        } else {
            Model.save() // to update UI
        }
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
    
    @objc private func itemCreated(_ notification: Notification) {
        guard let item = notification.object as? ArchivedItem else { return }
        collection.performBatchUpdates({
            filter.updateFilter(signalUpdate: false)
            if let index = filter.filteredDrops.firstIndex(of: item) {
                let n = IndexPath(item: index, section: 0)
                collection.insertItems(at: [n])
                updateEmptyView(animated: false)
            }
        }, completion: nil)
    }
    
    @objc private func modelDataUpdate(_ notification: Notification) {
        let parameters = notification.object as? [AnyHashable: Any]
        let savedUUIDs = parameters?["updated"] as? Set<UUID> ?? Set<UUID>()
        
        var removedItems = false
        collection.performBatchUpdates({

            let oldUUIDs = filter.filteredDrops.map { $0.uuid }
            filter.updateFilter(signalUpdate: false)
            if !Model.drops.contains(where: { !$0.shouldDisplayLoading }) {
                collection.reloadSections(IndexSet(integer: 0))
                return
            }
            let newUUIDs = filter.filteredDrops.map { $0.uuid }

            Set(oldUUIDs).union(newUUIDs).forEach { p in
                let oldIndex = oldUUIDs.firstIndex(of: p)
                let newIndex = newUUIDs.firstIndex(of: p)
                
                if let oldIndex = oldIndex, let newIndex = newIndex {
                    if oldIndex == newIndex, savedUUIDs.contains(p) { // update
                        let n = IndexPath(item: newIndex, section: 0)
                        collection.reloadItems(at: [n])
                    } else { // move
                        let i1 = IndexPath(item: oldIndex, section: 0)
                        let i2 = IndexPath(item: newIndex, section: 0)
                        collection.moveItem(at: i1, to: i2)
                    }
                } else if let newIndex = newIndex { // insert
                    let n = IndexPath(item: newIndex, section: 0)
                    collection.insertItems(at: [n])
                } else if let oldIndex = oldIndex { // remove
                    let o = IndexPath(item: oldIndex, section: 0)
                    collection.deleteItems(at: [o])
                    removedItems = true
                }
            }
        }, completion: { _ in
            if removedItems {
                self.itemsDeleted()
            }
        })
                
		updateUI()
	}

	private var emptyView: UIImageView?
	@objc private func updateUI() {
		editButton.isEnabled = !Model.drops.isEmpty

		selectedItems = selectedItems?.filter { uuid in Model.drops.contains { $0.uuid == uuid } }

		let selectedCount = selectedItems?.count ?? 0
		let someSelected = selectedCount > 0

        func setItemCountTitle(_ count: Int, _ text: String, colon: Bool) {
            let colonText = colon && collection.bounds.width > 512 ? ":" : ""
            itemsCount.title = "\(count) \(text)\(colonText)"
        }

		let itemCount = filter.filteredDrops.count
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

		let size = someSelected ? Model.sizeForItems(uuids: selectedItems ?? []) : filter.filteredSizeInBytes
		totalSizeLabel.title = diskSizeFormatter.string(fromByteCount: size)
		deleteButton.isEnabled = someSelected
		editLabelsButton.isEnabled = someSelected
		shareButton.isEnabled = someSelected

		updateLabelIcon()
		currentLabelEditor?.selectedItems = selectedItems
		collection.isAccessibilityElement = filter.filteredDrops.isEmpty
        
        updateEmptyView(animated: false)
	}

	@IBAction func shareButtonSelected(_ sender: UIBarButtonItem) {
		guard let selectedItems = selectedItems else { return }
        let sources = selectedItems.compactMap { Model.item(uuid: $0)?.mostRelevantTypeItem?.sharingActivitySource }
		if sources.isEmpty { return }
		let a = UIActivityViewController(activityItems: sources, applicationActivities: nil)
		a.completionWithItemsHandler = { [weak self] _, done, _, _ in
			if done {
				self?.setEditing(false, animated: true)
			}
		}
		present(a, animated: true)
        a.popoverPresentationController?.barButtonItem = sender
	}

	@IBAction private func sortAscendingButtonSelected() {
		let a = UIAlertController(title: "Sort", message: "Please select your preferred order.  This will sort your items once, it will not keep them sorted.", preferredStyle: .actionSheet)
		for sortOption in Model.SortOption.options {
			a.addAction(UIAlertAction(title: sortOption.ascendingTitle, style: .default) { _ in
				self.sortRequested(sortOption, ascending: true, button: self.sortAscendingButton)
			})
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
			let sortMethod = option.handlerForSort(itemsToSort: ContiguousArray(items), ascending: ascending)
			sortMethod()
			filter.updateFilter(signalUpdate: false)
			reloadData(onlyIfPopulated: false)
            Model.save()
		}
	}

	@IBAction private func itemsCountSelected(_ sender: UIBarButtonItem) {
		let selectedCount = (selectedItems?.count ?? 0)
		if selectedCount > 0 {
			let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
			let msg = selectedCount > 1 ? "Deselect \(selectedCount) Items" : "Deselect Item"
			a.addAction(UIAlertAction(title: msg, style: .default) { action in
				self.selectedItems?.removeAll()
                self.collection.reloadSections(IndexSet(integer: 0))
				self.updateUI()
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
			let itemCount = filter.filteredDrops.count
			guard itemCount > 0 else { return }
			let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
			let msg = itemCount > 1 ? "Select \(itemCount) Items" : "Select Item"
			a.addAction(UIAlertAction(title: msg, style: .default) { action in
                self.selectedItems = self.filter.filteredDrops.map { $0.uuid }
				self.collection.reloadData()
				self.updateUI()
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
	    filter.updateFilter(signalUpdate: true)
		updateLabelIcon()
        userActivity?.needsSave = true
	}

	private func updateLabelIcon() {
		if filter.isFilteringLabels {
			labelsButton.image = UIImage(systemName: "line.horizontal.3.decrease.circle.fill")
			labelsButton.accessibilityLabel = "Labels"
			labelsButton.accessibilityValue = "Active"
			title = filter.enabledLabelsForTitles.joined(separator: ", ")
		} else {
			labelsButton.image = UIImage(systemName: "line.horizontal.3.decrease.circle")
			labelsButton.accessibilityLabel = "Labels"
			labelsButton.accessibilityValue = "Inactive"
			title = "Gladys"
		}
        let haveDrops = !Model.drops.isEmpty
		labelsButton.isEnabled = haveDrops
		sortAscendingButton.isEnabled = haveDrops
	}

	private func blurb(_ message: String) {
		if let e = emptyView, !view.subviews.contains(where: { $0.tag == 9265 }) {
			let l = UILabel()
			l.tag = 9265
			l.translatesAutoresizingMaskIntoConstraints = false
			l.font = UIFont.preferredFont(forTextStyle: .caption2)
            l.textColor = .secondaryLabel
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

			DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
				UIView.animate(withDuration: 1, delay: 0, options: .curveEaseInOut, animations: {
					l.alpha = 0
				}, completion: { finished in
					l.removeFromSuperview()
				})
			}
		}
	}

	private func updateEmptyView(animated: Bool) {
		if Model.drops.isEmpty && emptyView == nil {
            let e = UIImageView(image: #imageLiteral(resourceName: "gladysImage"))
			e.isAccessibilityElement = false
            e.contentMode = .scaleAspectFit
			e.center(on: view)
            NSLayoutConstraint.activate([
                e.widthAnchor.constraint(equalToConstant: 160),
                e.heightAnchor.constraint(equalToConstant: 160)
            ])
			emptyView = e

			if animated {
				e.alpha = 0
				UIView.animate(animations: {
					e.alpha = 1
				})
			}

		} else if let e = emptyView, !Model.drops.isEmpty {
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
    
    @IBAction func editButtonSelected(_ sender: UIBarButtonItem) {
        setEditing(!isEditing, animated: true)
    }

	override func setEditing(_ editing: Bool, animated: Bool) {
		super.setEditing(editing, animated: animated)

		navigationController?.setToolbarHidden(!editing, animated: animated)
		if editing {
			selectedItems = [UUID]()
            editButton.title = "Done"
            editButton.image = UIImage(systemName: "ellipsis.circle.fill")
		} else {
			selectedItems = nil
            editButton.title = "Edit"
            editButton.image = UIImage(systemName: "ellipsis.circle")
			deleteButton.isEnabled = false
		}

		UIView.performWithoutAnimation {
			updateUI()
			for cell in collection.visibleCells as? [ArchivedItemCell] ?? [] {
				cell.isEditing = editing
			}
		}
	}
    
    private var itemSize: CGSize = .zero
    
	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		return itemSize
	}

	private func dragParameters(for indexPath: IndexPath) -> UIDragPreviewParameters? {
		let cell = collection.cellForItem(at: indexPath) as? ArchivedItemCell
        return cell?.dragParameters
	}

	func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
		return dragParameters(for: indexPath)
	}

	func collectionView(_ collectionView: UICollectionView, dropPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
		return dragParameters(for: indexPath)
	}

    func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard let uuid = configuration.identifier as? UUID, let item = Model.item(uuid: uuid), item.canPreview else {
            animator.preferredCommitStyle = .dismiss
            return
        }
        noteLastActioned(item: item)
        animator.preferredCommitStyle = .pop
        animator.addAnimations {
            if let index = self.filter.filteredDrops.firstIndex(of: item), let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? ArchivedItemCell {
                item.tryPreview(in: self, from: cell, forceFullscreen: false)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let item = filter.filteredDrops[indexPath.item]

        if item.flags.contains(.needsUnlock) {
            return UIContextMenuConfiguration(identifier: item.uuid as NSCopying, previewProvider: nil, actionProvider: { _ in
                let unlockAction = UIAction(title: "Unlock") { _ in
                    item.unlock(label: "Unlock Item", action: "Unlock") { success in
                        if success {
                            item.flags.remove(.needsUnlock)
                            item.postModified()
                        }
                    }
                }
                unlockAction.image = UIImage(systemName: "lock.open.fill")
                return UIMenu(title: "", image: nil, identifier: nil, options: [], children: [unlockAction])
            })
        }
        
        return UIContextMenuConfiguration(identifier: item.uuid as NSCopying, previewProvider: { [weak self] in
            guard let s = self else { return nil }
            if item.canPreview, let previewItem = item.previewableTypeItem {
                //if previewItem.isWebURL, let url = previewItem.encodedUrl {
                    //let x = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(identifier: "LinkPreview") as! LinkViewController
                    //x.url = url as URL
                    //return x
                //} else {
                    return previewItem.quickLook(in: s.view.window?.windowScene)
                //}
            } else {
                return nil
            }
        }, actionProvider: { [weak self] _ in
            return self?.createShortcutActions(for: item)
        })
    }

    private func passwordUpdate(_ newPassword: Data?, hint: String?, for item: ArchivedItem) {
        item.lockPassword = newPassword
        if let hint = hint, !hint.isEmpty {
            item.lockHint = hint
        } else {
            item.lockHint = nil
        }
        item.markUpdated()
        item.postModified()
        Model.save()
    }

    private func createShortcutActions(for item: ArchivedItem) -> UIMenu? {
        
        func makeAction(title: String, callback: @escaping () -> Void, style: UIAction.Attributes, iconName: String?) -> UIAction {
            let a = UIAction(title: title) { _ in callback() }
            a.attributes = style
            if let iconName = iconName {
                a.image = UIImage(systemName: iconName)
            }
            return a
        }
        
        var children = [UIMenuElement]()
        
        if item.canOpen {
            children.append(makeAction(title: "Open", callback: { [weak self] in
                self?.noteLastActioned(item: item)
                item.tryOpen(in: nil) { _ in }
            }, style: [], iconName: "arrow.up.doc"))
        }
        
        children.append(makeAction(title: "Info Panel", callback: { [weak self] in
            self?.noteLastActioned(item: item)
            self?.performSegue(withIdentifier: "showDetail", sender: item)
        }, style: [], iconName: "list.bullet.below.rectangle"))
        
        children.append(makeAction(title: "Move to Top", callback: { [weak self] in
            self?.noteLastActioned(item: item)
            Model.sendToTop(items: [item])
        }, style: [], iconName: "arrow.turn.left.up"))
        
        children.append(makeAction(title: "Copy to Clipboard", callback: { [weak self] in
            self?.noteLastActioned(item: item)
            item.copyToPasteboard()
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Copied.")
            }
        }, style: [], iconName: "doc.on.doc"))
        
        children.append(makeAction(title: "Duplicate", callback: { [weak self] in
            self?.noteLastActioned(item: item)
            Model.duplicate(item: item)
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Duplicated.")
            }
            }, style: [], iconName: "arrow.branch"))
        
        if !item.isImportedShare {
            if item.isLocked {
                children.append(makeAction(title: "Remove Lock", callback: {
                    item.unlock(label: "Remove Lock", action: "Remove") { [weak self] success in
                        if success {
                            self?.noteLastActioned(item: item)
                            self?.passwordUpdate(nil, hint: nil, for: item)
                        }
                    }
                }, style: [], iconName: "lock.slash"))
            } else {
                children.append(makeAction(title: "Add Lock", callback: {
                    item.lock { [weak self] passwordData, passwordHint in
                        if let d = passwordData {
                            self?.noteLastActioned(item: item)
                            self?.passwordUpdate(d, hint: passwordHint, for: item)
                        }
                    }
                }, style: [], iconName: "lock"))
            }
        }

        children.append(makeAction(title: "Siri Shortcuts", callback: { [weak self] in
            if let s = self,
                let index = s.filter.filteredDrops.firstIndex(of: item),
                let cell = s.collection.cellForItem(at: IndexPath(item: index, section: 0)) {
                self?.performSegue(withIdentifier: "toSiriShortcuts", sender: cell)
            }
        }, style: [], iconName: "mic"))
        
        if CloudManager.syncSwitchedOn {
            if item.shareMode == .none {
                children.append(makeAction(title: "Collaborate", callback: { [weak self] in
                    self?.addInvites(to: item)
                }, style: [], iconName: "person.crop.circle.badge.plus"))
                
            } else {
                children.append(makeAction(title: "Collaboration…", callback: { [weak self] in
                    if item.isPrivateShareWithOnlyOwner {
                        self?.shareOptionsPrivate(for: item)
                    } else if item.isShareWithOnlyOwner {
                        self?.shareOptionsPublic(for: item)
                    } else {
                        self?.editInvites(in: item)
                    }
                }, style: [], iconName: "person.crop.circle.fill.badge.checkmark"))
            }
        }

        if let m = item.mostRelevantTypeItem {
            children.append(makeAction(title: "Share", callback: { [weak self] in
                guard let s = self,
                    let index = s.filter.filteredDrops.firstIndex(of: item),
                    let cell = s.collection.cellForItem(at: IndexPath(item: index, section: 0)) as? ArchivedItemCell else {
                        return
                }
                
                s.noteLastActioned(item: item)
                let a = UIActivityViewController(activityItems: [m.sharingActivitySource], applicationActivities: nil)
                s.present(a, animated: true)
                if let p = a.popoverPresentationController {
                    p.sourceView = cell
                    p.sourceRect = cell.bounds.insetBy(dx: cell.bounds.width * 0.2, dy: cell.bounds.height * 0.2)
                }
            }, style: [], iconName: "square.and.arrow.up"))
        }
        
        let confirmTitle = item.shareMode == .sharing ? "Confirm (Will delete from shared users too)" : "Confirm Delete"
        let confirmAction = UIAction(title: confirmTitle) { _ in
            Model.delete(items: [item])
        }
        confirmAction.attributes = .destructive
        confirmAction.image = UIImage(systemName: "bin.xmark")
        let deleteMenu = UIMenu(title: "Delete", image: confirmAction.image, identifier: nil, options: .destructive, children: [confirmAction])
        children.append(deleteMenu)
        
        return UIMenu(title: "", image: nil, identifier: nil, options: [], children: children)
    }
    
    func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return previewForContextMenu(of: configuration)
    }
    
    func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return previewForContextMenu(of: configuration)
    }
    
    private func previewForContextMenu(of configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        if
            let uuid = configuration.identifier as? UUID,
            let item = Model.item(uuid: uuid),
            let index = filter.filteredDrops.firstIndex(of: item),
            let cell = collection.cellForItem(at: IndexPath(item: index, section: 0)) as? ArchivedItemCell {
            return cell.targetedPreviewItem
        }
        return nil
    }

	@objc private func forceLayout() {
        view.setNeedsLayout()
	}

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        let layout = (collection.collectionViewLayout as! UICollectionViewFlowLayout)
        let sinset = layout.sectionInset
        let insets = collection.safeAreaInsets
        let width = collection.bounds.size.width - insets.left - insets.right - sinset.left - sinset.right

        ////////////////////////////////////////
        
        func calculateSizes(for columnCount: CGFloat) {
            let extras = layout.minimumInteritemSpacing * (columnCount - 1)
            let side = ((width - extras) / columnCount).rounded(.down)
            itemSize = CGSize(width: side, height: side)
        }

        func calculateWideSizes(for columnCount: CGFloat) {
            let extras = layout.minimumInteritemSpacing * (columnCount - 1)
            let side = ((width - extras) / columnCount).rounded(.down)
            itemSize = CGSize(width: side, height: 80)
        }

        if PersistedOptions.wideMode {
            if width >= 768 {
                calculateWideSizes(for: 2)
            } else {
                itemSize = CGSize(width: width, height: 80)
            }
        } else {
            if width <= 320 && !PersistedOptions.forceTwoColumnPreference {
                itemSize = CGSize(width: 300, height: 200)
            } else if width >= 1366 {
                calculateSizes(for: 5)
            } else if width > 980 {
                calculateSizes(for: 4)
            } else if width > 438 {
                calculateSizes(for: 3)
            } else {
                calculateSizes(for: 2)
            }
        }
        
        view.window?.windowScene?.session.userInfo?["ItemSize"] = itemSize
        layout.invalidateLayout()

        log("Handlesize for: \(width), width: \(itemSize.width)")

        ///////////////////////////////
        
        let font: UIFont
        if width > 375 {
            font = UIFont.preferredFont(forTextStyle: .body)
        } else if width > 320 {
            let bodyFont = UIFont.preferredFont(forTextStyle: .body)
            font = bodyFont.withSize(bodyFont.pointSize - 2)
        } else {
            font = UIFont.preferredFont(forTextStyle: .caption1)
        }
        itemsCount.setTitleTextAttributes([.font: font], for: .normal)
        totalSizeLabel.setTitleTextAttributes([.font: font], for: .normal)
        
		shareButton.width = shareButton.image!.size.width + 22
		editLabelsButton.width = editLabelsButton.image!.size.width + 22
		deleteButton.width = deleteButton.image!.size.width + 22
		sortAscendingButton.width = sortAscendingButton.image!.size.width + 22
	}
        
	/////////////////////////////////

	private var selectedItems: [UUID]?
	@IBAction private func deleteButtonSelected(_ sender: UIBarButtonItem) {
		guard let candidates = selectedItems, !candidates.isEmpty else { return }

		let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		let msg = candidates.count > 1 ? "Delete \(candidates.count) Items" : "Delete Item"
		a.addAction(UIAlertAction(title: msg, style: .destructive) { action in
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
		guard let candidates = selectedItems, !candidates.isEmpty else { return }

		let itemsToDelete = Model.drops.filter { item -> Bool in
			candidates.contains(where: { $0 == item.uuid })
		}
		if !itemsToDelete.isEmpty {
			Model.delete(items: itemsToDelete)
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

    @objc private func dismissAnyPopoverRequested() {
        dismissAnyPopOver()
    }
    
    private func dismissAnyPopOver(completion: (()->Void)? = nil) {
        let firstPresentedAlertController = (navigationController?.presentedViewController ?? presentedViewController) as? UIAlertController
        firstPresentedAlertController?.dismiss(animated: true) {
            completion?()
        }
        let vc = firstPresentedNavigationController?.viewControllers.first
        vc?.dismiss(animated: true) {
            completion?()
        }
        if firstPresentedAlertController == nil && vc == nil {
            completion?()
        }
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

    private func itemsDeleted() {
        if filter.filteredDrops.isEmpty {
            
            if filter.isFiltering {
                resetSearch(andLabels: true)
            }
            
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

    @objc private func itemIngested(_ notification: Notification) {
        guard let item = notification.object as? ArchivedItem else { return }

		if let i = filter.filteredDrops.firstIndex(of: item) {
			mostRecentIndexPathActioned = IndexPath(item: i, section: 0)
			if currentDetailView == nil {
				focusInitialAccessibilityElement()
			}
		}

		if Model.doneIngesting {
			UIAccessibility.post(notification: .screenChanged, argument: nil)
		}
	}

	//////////////////////////

    @objc private func startSearch(_ notification: Notification) {
		if let s = navigationItem.searchController {
            if let initialText = notification.object as? String {
                s.searchBar.text = initialText
            }
			s.isActive = true
            s.searchBar.becomeFirstResponder()
		}
	}

	func resetSearch(andLabels: Bool) {
        
        dismissAnyPopOverOrModal()

		guard let s = navigationItem.searchController else { return }
		s.searchBar.text = nil

        s.delegate = nil
		s.isActive = false
        s.delegate = self

        if let layout = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            UIView.animate(animations: {
                var newInsets = layout.sectionInset
                newInsets.top = 0
                layout.sectionInset = newInsets
            })
        }

		if andLabels {
			filter.disableAllLabels()
			updateLabelIcon()
		}
	}

    @objc private func highlightItem(_ notification: Notification) {
        guard let request = notification.object as? HighlightRequest else { return }
        if let index = filter.filteredDrops.firstIndex(where: { $0.uuid.uuidString == request.uuid }) {
			dismissAnyPopOverOrModal() {
                self.highlightItem(at: index, andOpen: request.open, andPreview: request.preview, focusOnChild: request.focusOnChildUuid)
			}
        } else if let index = Model.drops.firstIndex(where: { $0.uuid.uuidString == request.uuid }) {
            self.resetSearch(andLabels: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.highlightItem(at: index, andOpen: request.open, andPreview: request.preview, focusOnChild: request.focusOnChildUuid)
            }
		}
	}

	private func highlightItem(at index: Int, andOpen: Bool, andPreview: Bool, focusOnChild childUuid: String?) {
		collection.isUserInteractionEnabled = false
		let ip = IndexPath(item: index, section: 0)
		collection.scrollToItem(at: ip, at: .centeredVertically, animated: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			if let cell = self.collection.cellForItem(at: ip) as? ArchivedItemCell {
				cell.flash()
                if let item = cell.archivedDropItem, !item.shouldDisplayLoading {
                    if andOpen {
                        self.mostRecentIndexPathActioned = ip
                        self.performSegue(withIdentifier: "showDetail", sender: item)

                    } else if andPreview, let presenter = self.view.window?.alertPresenter {
                        item.tryPreview(in: presenter, from: cell, preferChild: childUuid)
                    }
                }
			}
			self.collection.isUserInteractionEnabled = true
		}
	}

    func willPresentSearchController(_ searchController: UISearchController) {
        if let layout = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            UIView.animate(animations: {
                var newInsets = layout.sectionInset
                newInsets.top = 10
                layout.sectionInset = newInsets
            })
        }
    }
    
	func willDismissSearchController(_ searchController: UISearchController) {
		resetSearch(andLabels: false)
	}

	private var searchTimer: PopTimer!

	func updateSearchResults(for searchController: UISearchController) {
		searchTimer.push()
	}

    @objc private func reloadDataRequested(_ notification: Notification) {
        if self === notification.object as? ViewController { return } // ignore
        let onlyIfPopulated = notification.object as? Bool ?? false
        reloadData(onlyIfPopulated: onlyIfPopulated)
    }
    
    private func reloadData(onlyIfPopulated: Bool) {
		updateLabelIcon()
        if onlyIfPopulated && filter.filteredDrops.isEmpty {
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

	@objc private func forcePaste() {
		resetSearch(andLabels: true)
		pasteSelected(pasteButton)
	}

	///////////////////////////// Accessibility

	private var mostRecentIndexPathActioned: IndexPath?

    private func noteLastActioned(item: ArchivedItem) {
        if let i = filter.filteredDrops.firstIndex(of: item) {
			mostRecentIndexPathActioned = IndexPath(item: i, section: 0)
		}
	}

	private var closestIndexPathSinceLast: IndexPath? {
		let count = filter.filteredDrops.count
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
            UIKeyCommand.makeCommand(input: "v", modifierFlags: .command, action: #selector(pasteSelected(_:)), title: "Paste From Clipboard"),
			UIKeyCommand.makeCommand(input: "l", modifierFlags: .command, action: #selector(showLabels), title: "Labels Menu"),
			UIKeyCommand.makeCommand(input: "l", modifierFlags: [.command, .alternate], action: #selector(resetLabels), title: "Clear Active Labels"),
			UIKeyCommand.makeCommand(input: ",", modifierFlags: .command, action: #selector(showPreferences), title: "Preferences Menu"),
			UIKeyCommand.makeCommand(input: "f", modifierFlags: .command, action: #selector(openSearch), title: "Search Items"),
			UIKeyCommand.makeCommand(input: "e", modifierFlags: .command, action: #selector(toggleEdit), title: "Toggle Edit Mode")
		])
		return a
	}

	private var searchActive: Bool {
		return navigationItem.searchController?.isActive ?? false
	}
    
    override func updateUserActivityState(_ activity: NSUserActivity) {
        super.updateUserActivityState(activity)
        activity.title = title
        activity.userInfo = [kGladysMainViewLabelList: filter.enabledLabelsForTitles]
    }
    
    // MARK:

    private weak var itemToBeShared: ArchivedItem?
    
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        guard let item = itemToBeShared else { return }
        item.cloudKitShareRecord = csc.share
        item.postModified()
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        guard let i = itemToBeShared else { return }
        let wasImported = i.isImportedShare
        i.cloudKitShareRecord = nil
        if wasImported {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Model.delete(items: [i])
            }
        } else {
            i.postModified()
        }
    }

    func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
        guard let uuid = csc.share?.parent?.recordID.recordName, let item = Model.item(uuid: uuid), let ip = item.imagePath else {
            return nil
        }
        return dataAccessQueue.sync {
            return try? Data(contentsOf: ip)
        }
    }

    private func shareOptionsPrivate(for item: ArchivedItem) {
        let a = UIAlertController(title: "No Participants", message: "This item is shared privately, but has no participants yet. You can edit options to make it public, invite more people, or stop sharing it.", preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "Options", style: .default) { [weak self] _ in
            self?.editInvites(in: item)
        })
        a.addAction(UIAlertAction(title: "Stop Sharing", style: .destructive) { _ in
            CloudManager.deleteShare(item) { _ in }
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(a, animated: true)
        if let p = a.popoverPresentationController, let index = filter.filteredDrops.firstIndex(of: item), let cell = collection.cellForItem(at: IndexPath(item: index, section: 0)) {
            p.sourceView = cell
            p.sourceRect = cell.bounds
        }
    }

    private func shareOptionsPublic(for item: ArchivedItem) {
        let a = UIAlertController(title: "No Participants", message: "This item is shared publicly, but has no participants yet. You can edit options to make it private and invite people, or stop sharing it.", preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "Make Private", style: .default) { [weak self] _ in
            self?.editInvites(in: item)
        })
        a.addAction(UIAlertAction(title: "Stop Sharing", style: .destructive) { _ in
            CloudManager.deleteShare(item) { _ in }
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(a, animated: true)
        if let p = a.popoverPresentationController, let index = filter.filteredDrops.firstIndex(of: item), let cell = collection.cellForItem(at: IndexPath(item: index, section: 0)) {
            p.sourceView = cell
            p.sourceRect = cell.bounds
        }
    }

    private func addInvites(to item: ArchivedItem) {
        guard let rootRecord = item.cloudKitRecord else { return }
        let cloudSharingController = UICloudSharingController { controller, completion in
            CloudManager.share(item: item, rootRecord: rootRecord, completion: completion)
        }
        presentCloudController(cloudSharingController, for: item)
    }

    private func editInvites(in item: ArchivedItem) {
        guard let shareRecord = item.cloudKitShareRecord else { return }
        let cloudSharingController = UICloudSharingController(share: shareRecord, container: CloudManager.container)
        presentCloudController(cloudSharingController, for: item)
    }

    private func presentCloudController(_ cloudSharingController: UICloudSharingController, for item: ArchivedItem) {
        itemToBeShared = item
        cloudSharingController.delegate = self
        cloudSharingController.view.tintColor = view.tintColor
        present(cloudSharingController, animated: true)
        if let p = cloudSharingController.popoverPresentationController, let index = filter.filteredDrops.firstIndex(of: item), let cell = collection.cellForItem(at: IndexPath(item: index, section: 0)) {
            p.sourceView = cell
            p.sourceRect = cell.bounds
        }
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        genericAlert(title: "Could not share this item", message: error.finalDescription)
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        return itemToBeShared?.trimmedSuggestedName
    }
}
