import UIKit
import Intents

extension UIKeyCommand {
    static func makeCommand(input: String, modifierFlags: UIKeyModifierFlags, action: Selector, title: String) -> UIKeyCommand {
        let c = UIKeyCommand(input: input, modifierFlags: modifierFlags, action: action)
        c.title = title
        return c
    }
}

var currentWindow: UIWindow? {
    return UIApplication.shared.connectedScenes.filter { $0.activationState != .background }.compactMap { ($0 as? UIWindowScene)?.windows.first }.lazy.first
}

weak var lastUsedWindow: UIWindow?

@discardableResult
func genericAlert(title: String?, message: String?, autoDismiss: Bool = true, buttonTitle: String? = "OK", offerSettingsShortcut: Bool = false, completion: (() -> Void)? = nil) -> UIAlertController {
        
	let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
	if let buttonTitle = buttonTitle {
		a.addAction(UIAlertAction(title: buttonTitle, style: .default) { _ in completion?() })
	}
    
    if offerSettingsShortcut {
        a.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:]) { _ in
                completion?()
            }
        })
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

func getInput(from: UIViewController, title: String, action: String, previousValue: String?, completion: @escaping (String?) -> Void) {
	let a = UIAlertController(title: title, message: nil, preferredStyle: .alert)
	a.addTextField { textField in
		textField.placeholder = title
		textField.text = previousValue
	}
	a.addAction(UIAlertAction(title: action, style: .default) { _ in
		let result = a.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		completion(result)
	})
	a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
		completion(nil)
	})
	from.present(a, animated: true)
}

final class ViewController: GladysViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching,
	UISearchControllerDelegate, UISearchResultsUpdating, UICollectionViewDropDelegate, UICollectionViewDragDelegate,
    UIPopoverPresentationControllerDelegate, UICloudSharingControllerDelegate, ModelFilterContextDelegate {
    
	@IBOutlet private var collection: UICollectionView!
	@IBOutlet private var totalSizeLabel: UIBarButtonItem!
	@IBOutlet private var deleteButton: UIBarButtonItem!
	@IBOutlet private var editLabelsButton: UIBarButtonItem!
	@IBOutlet private var sortAscendingButton: UIBarButtonItem!
	@IBOutlet private var labelsButton: UIBarButtonItem!
	@IBOutlet private var settingsButton: UIBarButtonItem!
	@IBOutlet private var itemsCount: UIBarButtonItem!
	@IBOutlet private var dragModePanel: UIView!
	@IBOutlet private var dragModeTitle: UILabel!
    @IBOutlet private var dragModeSubtitle: UILabel!
	@IBOutlet private var shareButton: UIBarButtonItem!
    @IBOutlet private var editButton: UIBarButtonItem!
    
    var filter: ModelFilterContext!
    
	var itemView: UICollectionView {
		return collection!
	}

	/////////////////////////////

	private var dragModeReverse = false
    
    override var title: String? {
        didSet {
            updateTitle()
        }
    }
    
    private func updateTitle() {
        guard let scene = viewIfLoaded?.window?.windowScene else {
            return
        }
        
        guard let filter = filter else {
            scene.title = nil
            return
        }
        
        var components = filter.enabledLabelsForTitles
        
        if filter.isFilteringText, let searchText = filter.text {
            components.insert("\"\(searchText)\"", at: 0)
        }
                
        if components.isEmpty {
            scene.title = nil
        } else {
            scene.title = components.joined(separator: ", ")
        }
    }

	private func showDragModeOverlay(_ show: Bool) {
		if dragModePanel.superview != nil, !show {
			UIView.animate(withDuration: 0.1) {
				self.dragModePanel.alpha = 0
                self.dragModePanel.transform = CGAffineTransform(translationX: 0, y: -44)
			} completion: { _ in
				self.dragModePanel.removeFromSuperview()
			}
		} else if dragModePanel.superview == nil, show, let n = navigationController {
			dragModeReverse = false
			updateDragModeOverlay()
            n.view.addSubview(dragModePanel)
			NSLayoutConstraint.activate([
				dragModePanel.centerXAnchor.constraint(equalTo: collection.centerXAnchor),
                dragModePanel.topAnchor.constraint(equalTo: n.view.topAnchor)
				])
            self.dragModePanel.transform = CGAffineTransform(translationX: 0, y: -44)
			UIView.animate(withDuration: 0.1) {
				self.dragModePanel.alpha = 1
                self.dragModePanel.transform = .identity
			}
		}
	}
    
    func modelFilterContextChanged(_ modelFilterContext: ModelFilterContext, animate: Bool) {
        updateDataSource(animated: animate)
        updateLabelIcon()
    }

	@IBAction private func dragModeButtonSelected(_ sender: UIButton) {
		dragModeReverse = !dragModeReverse
		updateDragModeOverlay()
	}

	private func updateDragModeOverlay() {
		if dragModeMove {
			dragModeTitle.text = "Moving"
			dragModeSubtitle.text = "Copy instead"
		} else {
			dragModeTitle.text = "Copying"
			dragModeSubtitle.text = "Move instead"
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
        if let item = item(for: indexPath), !item.flags.contains(.needsUnlock) {
            return [item.dragItem]
        }
        return []
	}

	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        guard let item = item(for: indexPath) else { return [] }
		let dragItem = item.dragItem
        if session.localContext as? String == "typeItem" || session.items.contains(dragItem) || item.flags.contains(.needsUnlock) {
			return []
		} else {
			return [dragItem]
		}
	}

	func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
		for indexPath in indexPaths {
            if let item = item(for: indexPath) {
                ArchivedItemCell.warmUp(for: item)
            }
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
    
    private func path(at point: CGPoint) -> IndexPath {
        var rects = [Int: CGRect]()
        for cell in collection.visibleCells {
            guard let indexPath = collection.indexPath(for: cell) else {
                continue
            }
            let frame = cell.frame
            if frame.contains(point) {
                return indexPath
            }
            let wideFrame = CGRect(x: 0, y: frame.origin.y, width: collection.bounds.width, height: frame.height)
            if let existingRect = rects[indexPath.section] {
                rects[indexPath.section] = existingRect.union(wideFrame)
            } else {
                rects[indexPath.section] = wideFrame
            }
        }
        if let rect = rects.first(where: { $0.value.contains(point) }) {
            let section = rect.key
            let itemCount = collection.numberOfItems(inSection: section)
            return IndexPath(item: itemCount, section: section)
        }
        return IndexPath(item: 0, section: 0)
    }
    
    private func insert(item: ArchivedItem, at destinationIndexPath: IndexPath, offset: Int = 0) {
        if let uuid = dataSource.itemIdentifier(for: destinationIndexPath)?.uuid, let index = Model.firstIndexOfItem(with: uuid) {
            Model.drops.insert(item, at: index + offset)
        } else {
            Model.drops.append(item)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
                        
        coordinator.session.progressIndicatorStyle = .none
        
        var needsPost = false
        var needsFullSave = false
        var needsSaveIndex = false
        
        let destinationIndexPath = coordinator.destinationIndexPath ?? path(at: coordinator.session.location(in: collectionView))
        let sectionPath = IndexPath(item: 0, section: destinationIndexPath.section)

        for coordinatorItem in coordinator.items {
            let dragItem = coordinatorItem.dragItem
            
            if let existingItem = dragItem.localObject as? ArchivedItem {
                // Gladys to Gladys
                Component.droppedIds.remove(existingItem.uuid) // do not count this as an external drop
                if let modelSourceIndex = Model.firstIndexOfItem(with: existingItem.uuid) {

                    Model.drops.remove(at: modelSourceIndex)
                    
                    switch filter.groupingMode {
                    case .byLabel:
                        if let sourceIndexPath = coordinatorItem.sourceIndexPath,
                           let destinationSectionLabel = dataSource.itemIdentifier(for: sectionPath)?.section?.name,
                           let sourceSectionLabel = dataSource.itemIdentifier(for: sourceIndexPath)?.section?.name,
                           sourceSectionLabel != destinationSectionLabel {
                            // drag between sections in same window
                            insert(item: existingItem, at: destinationIndexPath)

                            let oldLabels = existingItem.labels
                            existingItem.labels.removeAll { $0 == sourceSectionLabel }
                            if !existingItem.labels.contains(destinationSectionLabel) {
                                existingItem.labels.append(destinationSectionLabel)
                            }
                            if oldLabels == existingItem.labels {
                                needsSaveIndex = true
                            } else {
                                existingItem.markUpdated()
                                needsFullSave = true
                            }
                            
                        } else if let sourceIndexPath = coordinatorItem.sourceIndexPath {
                            // drag inside same section
                            if sourceIndexPath.item <= destinationIndexPath.item {
                                insert(item: existingItem, at: destinationIndexPath, offset: 1)
                            } else {
                                insert(item: existingItem, at: destinationIndexPath)
                            }

                            needsSaveIndex = true
                            
                        } else if let destinationSectionLabel = dataSource.itemIdentifier(for: sectionPath)?.section?.name {
                            // drag into section from another Gladys window
                            insert(item: existingItem, at: destinationIndexPath)

                            if !existingItem.labels.contains(destinationSectionLabel) {
                                existingItem.labels.append(destinationSectionLabel)
                                existingItem.markUpdated()
                                needsFullSave = true
                            } else {
                                needsSaveIndex = true
                            }
                        }
                        
                    case .flat:
                        // gladys-to-gladys
                        if let sourceIndexPath = coordinatorItem.sourceIndexPath, sourceIndexPath.item < destinationIndexPath.item {
                            insert(item: existingItem, at: destinationIndexPath, offset: 1)
                        } else {
                            // also covers case of another window
                            insert(item: existingItem, at: destinationIndexPath)
                        }
                        if !PersistedOptions.dontAutoLabelNewItems && filter.isFilteringLabels && existingItem.labels != filter.enabledLabelsForItems {
                            existingItem.labels = Array(Set(existingItem.labels).union(filter.enabledLabelsForItems))
                            existingItem.postModified()
                            existingItem.markUpdated()
                            needsFullSave = true
                        } else {
                            needsSaveIndex = true
                        }
                    }
                }
                
            } else {
                // External to Gladys
                
                for newItem in ArchivedItem.importData(providers: [dragItem.itemProvider], overrides: nil) {
                    switch filter.groupingMode {
                    case .byLabel:
                        if let destinationSectionLabel = dataSource.itemIdentifier(for: sectionPath)?.section?.name {
                            newItem.labels.append(destinationSectionLabel)
                        }
                        insert(item: newItem, at: destinationIndexPath)

                    case .flat:
                        if !PersistedOptions.dontAutoLabelNewItems && filter.isFilteringLabels {
                            newItem.labels = filter.enabledLabelsForItems
                        }
                        insert(item: newItem, at: destinationIndexPath)
                    }
                    // needsFullSave = true // ingest will take care of this - do not save here, dangerous
                    needsPost = true
                }
            }
            
            filter.updateFilter(signalUpdate: .instant)
            coordinator.drop(dragItem, toItemAt: destinationIndexPath)
            mostRecentIndexPathActioned = destinationIndexPath
        }
        
        if needsPost {
            self.focusInitialAccessibilityElement()
            self.updateEmptyView()
        }
        
        if needsFullSave {
            Model.save()
        } else if needsSaveIndex {
            Model.saveIndexOnly()
        }
        
        self.collection.isAccessibilityElement = false
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
        } else if (Singleton.shared.componentDropActiveFromDetailView == nil && currentDetailView != nil) || currentLabelSelector != nil {
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
				let p = t.popoverPresentationController,
                let myNavView = navigationController?.view
				else { return }

			p.permittedArrowDirections = [.any]
			p.sourceRect = CGRect(origin: CGPoint(x: 15, y: 15), size: CGSize(width: 44, height: 44))
			p.sourceView = myNavView
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

            d.sourceIndexPath = indexPath
			d.item = item

            p.popoverBackgroundViewClass = GladysPopoverBackgroundView.self
			p.permittedArrowDirections = PersistedOptions.wideMode ? [.left, .right] : [.any]
			p.sourceView = myNavView
            p.sourceRect = cell.convert(cell.bounds.insetBy(dx: cell.bounds.width * 0.3, dy: cell.bounds.height * 0.3), to: myNavView)
			p.delegate = self

			if Singleton.shared.componentDropActiveFromDetailView != nil {
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
            e.selectedItems = selectedItems.map { $0.uuid }
			e.endCallback = { [weak self] hasChanges in
				if hasChanges {
					self?.setEditing(false, animated: true)
				}
			}
            
        case "toSiriShortcuts":
            guard let n = segue.destination as? UINavigationController,
                let d = n.viewControllers.first as? SiriShortcutsViewController,
                let cell = sender as? ArchivedItemCell,
                let item = cell.archivedDropItem
                else { return }
            
            d.sourceItem = item
            if let p = n.popoverPresentationController {
                p.sourceView = cell
                p.delegate = self
            }
        
        default: break
		}
	}

	private func trackCellForAWhile(_ cell: UICollectionViewCell, for popOver: UIPopoverPresentationController, in container: UIView) {
		var observation: NSKeyValueObservation?
		observation = cell.observe(\.center, options: .new) { strongCell, _ in
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
    
    private func item(for indexPath: IndexPath) -> ArchivedItem? {
        if let uuid = dataSource.itemIdentifier(for: indexPath)?.uuid {
            return Model.item(uuid: uuid)
        }
        return nil
    }
    
    private func cell(for identifier: ItemIdentifier) -> ArchivedItemCell? {
        if let indexPath = dataSource.indexPath(for: identifier), let cell = dataSource.collectionView(collection, cellForItemAt: indexPath) as? ArchivedItemCell {
            return cell
        }
        return nil
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if collectionView.hasActiveDrop && Singleton.shared.componentDropActiveFromDetailView == nil { return false }
        guard let item = item(for: indexPath) else {
            return false
        }
        return !item.shouldDisplayLoading
    }
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        updateUI()
    }
    
	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isEditing {
            updateUI()
            return
        }
        
        collectionView.deselectItem(at: indexPath, animated: false)
        
        guard let item = item(for: indexPath) else {
            return
        }
        
		if item.flags.contains(.needsUnlock) {
			mostRecentIndexPathActioned = indexPath
            item.unlock(label: "Unlock Item", action: "Unlock") { success in
                if success {
                    item.flags.remove(.needsUnlock)
                    item.postModified()
                }
            }
            return
            
        }
        
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

    @objc private func pinched(_ pinchRecognizer: CenteredPinchGestureRecognizer) {
        if
            pinchRecognizer.state == .changed,
            pinchRecognizer.velocity > 3,
            let startPoint = pinchRecognizer.startPoint,
            let recognizerView = pinchRecognizer.view,
            let itemIndexPath = collection.indexPathForItem(at: collection.convert(startPoint, from: recognizerView)),
            let cell = collection.cellForItem(at: itemIndexPath) as? ArchivedItemCell,
            let item = cell.archivedDropItem,
            !item.shouldDisplayLoading,
            item.canPreview,
            !item.flags.contains(.needsUnlock),
            let presenter = view.window?.alertPresenter {
            
            item.tryPreview(in: presenter, from: cell)
            pinchRecognizer.state = .ended
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
		dragModePanel.layer.shadowOffset = CGSize(width: 0, height: 1)
		dragModePanel.layer.shadowOpacity = 0.3
		dragModePanel.layer.shadowRadius = 2
		dragModePanel.layer.cornerRadius = 20
        dragModePanel.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]
		dragModePanel.alpha = 0
	}
    
    var onLoad: ((ViewController) -> Void)?
        
    private lazy var dataSource = UICollectionViewDiffableDataSource<SectionIdentifier, ItemIdentifier>(collectionView: collection) { [weak self] collectionView, indexPath, sectionItem in
        let type = PersistedOptions.wideMode ? "WideArchivedItemCell" : "ArchivedItemCell"
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: type, for: indexPath) as! ArchivedItemCell
        if let self = self {
            cell.lowMemoryMode = self.lowMemoryMode
            cell.archivedDropItem = Model.item(uuid: sectionItem.uuid)
            cell.isEditing = self.isEditing
        }
        return cell
    }
    
    private var collapsedToggles = Set<String>()
    
    private func updateDataSource(reloading: Set<UUID>? = nil, animated: Bool = true) {
        let toggles = filter.enabledToggles
        
        let drops = filter.filteredDrops
        var labelLookups = [String: [UUID]]()
        
        switch filter.groupingMode {
        case .byLabel:
            labelLookups.reserveCapacity(toggles.count)
            for item in drops {
                if item.labels.isEmpty {
                    let label = "Items with no labels"
                    if var list = labelLookups[label] {
                        list.append(item.uuid)
                        labelLookups[label] = list
                    } else {
                        labelLookups[label] = [item.uuid]
                    }
                } else {
                    for label in item.labels {
                        if var list = labelLookups[label] {
                            list.append(item.uuid)
                            labelLookups[label] = list
                        } else {
                            labelLookups[label] = [item.uuid]
                        }
                    }
                }
            }
        case .flat:
            collapsedToggles.removeAll()
            labelLookups[""] = drops.map { $0.uuid }
        }

        var snapshot = NSDiffableDataSourceSnapshot<SectionIdentifier, ItemIdentifier>()
        let reloadRequest = reloading ?? Set<UUID>()
        var itemsToReload = [ItemIdentifier]()
        
        switch filter.groupingMode {
        case .byLabel:
            toggles.forEach { toggle in
                if let sectionItems = labelLookups[toggle.name]?.map({ ItemIdentifier(section: toggle, uuid: $0) }), !sectionItems.isEmpty {
                    let collapsed = collapsedToggles
                    let sectionIdentifier = SectionIdentifier(section: toggle, expanded: !collapsed.contains(toggle.name))
                    snapshot.appendSections([sectionIdentifier])
                    if !collapsed.contains(toggle.name) {
                        snapshot.appendItems(sectionItems, toSection: sectionIdentifier)
                        let reloadInThisSection = sectionItems.filter { reloadRequest.contains($0.uuid) }
                        itemsToReload.append(contentsOf: reloadInThisSection)
                    }
                }
            }
        case .flat:
            let section = SectionIdentifier(section: nil, expanded: true)
            snapshot.appendSections([section])
            let identifiers = drops.map { ItemIdentifier(section: nil, uuid: $0.uuid) }
            snapshot.appendItems(identifiers)
            itemsToReload = identifiers.filter { reloadRequest.contains($0.uuid) }
        }
        
        if !itemsToReload.isEmpty {
            snapshot.reloadItems(itemsToReload)
        }
        dataSource.apply(snapshot, animatingDifferences: animated && !firstAppearance)
    }
    
    private func headerSelected(for identifier: SectionIdentifier, view: LabelSectionTitle) {
        guard let name = identifier.section?.name else { return }
        if collapsedToggles.remove(name) == nil {
            collapsedToggles.insert(name)
        }
        updateDataSource()
    }
    
	override func viewDidLoad() {
		super.viewDidLoad()
        
        collection.reorderingCadence = .slow
		collection.accessibilityLabel = "Items"
		collection.dragInteractionEnabled = true
        collection.dataSource = dataSource
        collection.contentOffset = .zero
        
        let headerRegistration = UICollectionView.SupplementaryRegistration<LabelSectionTitle>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] titleView, _, indexPath in
            guard let self = self else { return }
            let toggle = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
            titleView.configure(with: toggle) { [weak self] in
                self?.headerSelected(for: toggle, view: titleView)
            }
            titleView.menuOptions = [
                UIAction(title: "Expand All", image: UIImage(systemName: "rectangle.expand.vertical")) { [weak self] _ in
                    guard let self = self else { return }
                    self.collapsedToggles.removeAll()
                    self.updateDataSource()
                },
                UIAction(title: "Collapse All", image: UIImage(systemName: "arrow.up.to.line")) { [weak self] _ in
                    guard let self = self else { return }
                    self.collapsedToggles = Set(self.dataSource.snapshot().sectionIdentifiers.compactMap { $0.section?.name })
                    self.updateDataSource()
                }
            ]
        }
                
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
        
        updateDataSource()

		navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor.g_colorLightGray
		]
		navigationController?.navigationBar.largeTitleTextAttributes = [
            .foregroundColor: UIColor.g_colorLightGray
		]

		let searchController = UISearchController(searchResultsController: nil)
		searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
		searchController.delegate = self
		searchController.searchResultsUpdater = self
        searchController.searchBar.returnKeyType = .search
        searchController.searchBar.enablesReturnKeyAutomatically = false
		navigationItem.searchController = searchController

		searchTimer = PopTimer(timeInterval: 0.4) { [weak searchController, weak self] in
            self?.filter.text = searchController?.searchBar.text
			self?.updateUI()
		}

		navigationController?.setToolbarHidden(true, animated: false)

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(labelSelectionChanged), name: .LabelSelectionChanged, object: nil)
        n.addObserver(self, selector: #selector(reloadExistingItems(_:)), name: .ItemCollectionNeedsDisplay, object: nil)
		n.addObserver(self, selector: #selector(modelDataUpdate(_:)), name: .ModelDataUpdated, object: nil)
        n.addObserver(self, selector: #selector(itemCreated(_:)), name: .ItemAddedBySync, object: nil)
		n.addObserver(self, selector: #selector(cloudStatusChanged), name: .CloudManagerStatusChanged, object: nil)
		n.addObserver(self, selector: #selector(reachabilityChanged), name: .ReachabilityChanged, object: nil)
		n.addObserver(self, selector: #selector(acceptStarted), name: .AcceptStarting, object: nil)
		n.addObserver(self, selector: #selector(acceptEnded), name: .AcceptEnding, object: nil)
        n.addObserver(self, selector: #selector(itemIngested(_:)), name: .IngestComplete, object: nil)
        n.addObserver(self, selector: #selector(highlightItem(_:)), name: .HighlightItemRequested, object: nil)
        n.addObserver(self, selector: #selector(uiRequest(_:)), name: .UIRequest, object: nil)
        n.addObserver(self, selector: #selector(dismissAnyPopoverRequested), name: .DismissPopoversRequest, object: nil)
        n.addObserver(self, selector: #selector(resetSearchRequest), name: .ResetSearchRequest, object: nil)
        n.addObserver(self, selector: #selector(startSearch(_:)), name: .StartSearchRequest, object: nil)
        n.addObserver(self, selector: #selector(forcePaste), name: .ForcePasteRequest, object: nil)
        n.addObserver(self, selector: #selector(keyboardHiding), name: UIApplication.keyboardWillHideNotification, object: nil)
        
        if filter.isFilteringLabels { // in case we're restored with active labels
            filter.updateFilter(signalUpdate: .none)
        }

        updateUI()
		emptyView?.alpha = 1
        blurb(Greetings.openLine)

		cloudStatusChanged()
        
        dismissOnNewWindow = false
        autoConfigureButtons = true
        
        userActivity = NSUserActivity(activityType: kGladysMainListActivity)
        userActivity?.needsSave = true
        
        let p = CenteredPinchGestureRecognizer(target: self, action: #selector(pinched(_ :)))
        for r in collection.gestureRecognizers ?? [] where r.name?.hasPrefix("multi-select.") == true {
            r.require(toFail: p)
        }
        collection.addGestureRecognizer(p)
	}
    
    override func viewDidAppear(_ animated: Bool) {

        if firstAppearance {
            if let search = filter.text, !search.isEmpty, let sc = navigationItem.searchController {
                sc.searchBar.text = search
                searchTimer.abort()
                updateSearchResults(for: sc)
            }
            updateTitle()
        }
        
        super.viewDidAppear(animated)

        if let o = onLoad {
            o(self)
            onLoad = nil
        }
    }
    
    @objc private func keyboardHiding() {
        if self.presentedViewController != nil {
            return
        }
        if currentDetailView != nil {
            return
        }
        if !filter.isFilteringText {
            resetSearch(andLabels: false)
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

	@objc private func reachabilityChanged() {
        if reachability.status == .reachableViaWiFi && CloudManager.syncContextSetting == .wifiOnly {
			CloudManager.opportunisticSyncIfNeeded()
		}
	}

	@objc private func refreshControlChanged(_ sender: UIRefreshControl) {
		guard let r = collection.refreshControl else { return }
		if r.isRefreshing && !CloudManager.syncing {
			CloudManager.sync(overridingUserPreference: true) { error in
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
        
        if CloudManager.syncing || CloudManager.syncTransitioning {
            collection.accessibilityLabel = CloudManager.syncString
        } else {
            collection.accessibilityLabel = "Items"
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

	@IBOutlet private var pasteButton: UIBarButtonItem!

	@IBAction private func pasteSelected(_ sender: UIBarButtonItem) {
        Model.donatePasteIntent()
        if Model.pasteItems(from: UIPasteboard.general.itemProviders, overrides: nil) == .noData {
            genericAlert(title: "Nothing to Paste", message: "There is currently nothing in the clipboard.")
        }
	}

	private var lowMemoryMode = false {
		didSet {
            if lowMemoryMode != oldValue {
                for cell in collection.visibleCells as? [ArchivedItemCell] ?? [] {
                    cell.lowMemoryMode = lowMemoryMode
                }
            }
		}
	}

	override func didReceiveMemoryWarning() {
		if UIApplication.shared.applicationState == .background {
			log("Placing UI in background low-memory mode")
			lowMemoryMode = true
		}
		super.didReceiveMemoryWarning()
	}

    func sceneForegrounded() {
        lowMemoryMode = false
		if emptyView != nil {
			blurb(Greetings.randomGreetLine)
		}
	}
    
    @objc private func itemCreated(_ notification: Notification) {
        guard let item = notification.object as? ArchivedItem else { return }
        filter.updateFilter(signalUpdate: .none)
        if filter.filteredDrops.contains(item) {
            updateDataSource()
            updateEmptyView()
        }
    }
    
    @objc private func modelDataUpdate(_ notification: Notification) {
        let oldUUIDs = filter.filteredDrops.map { $0.uuid }
        filter.updateFilter(signalUpdate: .none)
        let oldSet = Set(oldUUIDs)

        let parameters = notification.object as? [AnyHashable: Any]
        let uuidsToReload = (parameters?["updated"] as? Set<UUID>)?.intersection(oldSet)
        updateDataSource(reloading: uuidsToReload)
        
        if !Model.drops.isEmpty && Model.drops.allSatisfy({ $0.shouldDisplayLoading }) {
            return
        }
        
        let newUUIDs = filter.filteredDrops.map { $0.uuid }
        let newSet = Set(newUUIDs)
        
        let removed = oldSet.subtracting(newSet)
        let added = newSet.subtracting(oldSet)
        
        let removedItems = !removed.isEmpty
        let ipsInsered = !added.isEmpty
        let ipsMoved = !removedItems && !ipsInsered && oldUUIDs != newUUIDs
                
        if removedItems || ipsInsered || ipsMoved {
            if !phoneMode, let vc = (currentDetailView ?? currentPreviewView) {
                vc.dismiss(animated: false)
            }
            
            if removedItems {
                if filter.filteredDrops.isEmpty {
                    
                    if filter.isFiltering {
                        resetSearch(andLabels: true)
                    }

                    setEditing(false, animated: true)
                    mostRecentIndexPathActioned = nil
                    blurb(Greetings.randomCleanLine)
                }
                focusInitialAccessibilityElement()
            }
        }
                
        updateUI()
    }

	private var emptyView: UIImageView?
	@objc private func updateUI() {
        if Model.drops.isEmpty {
            editButton.isEnabled = false
            if isEditing {
                setEditing(false, animated: true)
            }
        } else {
            editButton.isEnabled = true
        }

		let selectedCount = selectedItems.count
		let someSelected = selectedCount > 0

        func setItemCountTitle(_ count: Int, _ text: String, colon: Bool) {
            let colonText = colon && collection.bounds.width > 512 ? ":" : ""
            itemsCount.title = "\(count) \(text)\(colonText)"
        }

        let filteredDrops = filter.filteredDrops
		let itemCount = filteredDrops.count
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

        totalSizeLabel.title = "…"
        let selected = selectedItems
        imageProcessingQueue.async {
            let drops: ContiguousArray<ArchivedItem>
            if !selected.isEmpty {
                drops = filteredDrops.filter { selected.contains($0) }
            } else {
                drops = filteredDrops
            }
            let size = drops.reduce(0) { $0 + $1.sizeInBytes }
            let sizeLabel = diskSizeFormatter.string(fromByteCount: size)
            DispatchQueue.main.async {
                self.totalSizeLabel.title = sizeLabel
            }
        }
		deleteButton.isEnabled = someSelected
		editLabelsButton.isEnabled = someSelected
		shareButton.isEnabled = someSelected

		updateLabelIcon()
        currentLabelEditor?.selectedItems = selectedItems.map { $0.uuid }
		collection.isAccessibilityElement = filteredDrops.isEmpty

        updateEmptyView()
	}

	@IBAction private func shareButtonSelected(_ sender: UIBarButtonItem) {
        let sources = selectedItems.compactMap { $0.mostRelevantTypeItem?.sharingActivitySource }
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
		let items = ignoreSelectedItems ? [] : selectedItems
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
            filter.updateFilter(signalUpdate: .none)
            Model.save()
		}
	}

	@IBAction private func itemsCountSelected(_ sender: UIBarButtonItem) {
		let selectedCount = selectedItems.count
		if selectedCount > 0 {
			let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
			let msg = selectedCount > 1 ? "Deselect \(selectedCount) Items" : "Deselect Item"
			a.addAction(UIAlertAction(title: msg, style: .default) { _ in
                self.deselectAll()
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
			a.addAction(UIAlertAction(title: msg, style: .default) { _ in
                self.selectAll(nil)
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
        filter.updateFilter(signalUpdate: .animated)
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
				l.widthAnchor.constraint(equalTo: e.widthAnchor)
			])

			DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
				UIView.animate(withDuration: 1, delay: 0, options: .curveEaseInOut, animations: {
					l.alpha = 0
				}, completion: { _ in
					l.removeFromSuperview()
				})
			}
		}
	}

	private func updateEmptyView() {
		if Model.drops.isEmpty && emptyView == nil {
            let e = UIImageView(image: #imageLiteral(resourceName: "gladysImage"))
			e.isAccessibilityElement = false
            e.contentMode = .scaleAspectFit
            e.alpha = 0
			e.center(on: view)
            NSLayoutConstraint.activate([
                e.widthAnchor.constraint(equalToConstant: 160),
                e.heightAnchor.constraint(equalToConstant: 160)
            ])
			emptyView = e

            UIView.animate(animations: {
                e.alpha = 1
            })
		
		} else if let e = emptyView, !Model.drops.isEmpty {
			emptyView = nil
            UIView.animate(animations: {
                e.alpha = 0
            }, completion: { _ in
                e.removeFromSuperview()
            })
		}
	}
    
    @IBAction private func editButtonSelected(_ sender: UIBarButtonItem) {
        setEditing(!isEditing, animated: true)
    }
    
    private var selectedItems: [ArchivedItem] {
        return (collection.indexPathsForSelectedItems ?? []).compactMap { item(for: $0) }
    }

	override func setEditing(_ editing: Bool, animated: Bool) {
		super.setEditing(editing, animated: animated)

        if editing {
            collection.allowsMultipleSelection = true
            collection.allowsMultipleSelectionDuringEditing = true
            navigationController?.setToolbarHidden(false, animated: animated)
            editButton.title = "Done"
            editButton.image = UIImage(systemName: "ellipsis.circle.fill")
            updateUI()

		} else {
            collection.allowsMultipleSelection = false
            collection.allowsMultipleSelectionDuringEditing = false
            navigationController?.setToolbarHidden(true, animated: animated)
            editButton.title = "Edit"
            editButton.image = UIImage(systemName: "ellipsis.circle")
            deselectAll() // calls updateUI
		}
        
        for cell in collection.visibleCells as? [ArchivedItemCell] ?? [] {
            cell.isEditing = editing
        }
	}
    
    override func selectAll(_ sender: Any?) {
        // super not called intentionally
        if collection.numberOfSections == 0 {
            return
        }
        for ip in 0 ..< collection.numberOfItems(inSection: 0) {
            collection.selectItem(at: IndexPath(item: ip, section: 0), animated: false, scrollPosition: .centeredHorizontally)
        }
        updateUI()
    }
    
    private func deselectAll() {
        collection.selectItem(at: nil, animated: false, scrollPosition: .centeredHorizontally)
        updateUI()
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
        guard
            let indexPath = configuration.identifier as? IndexPath,
            let item = item(for: indexPath),
            item.canPreview else {
                animator.preferredCommitStyle = .dismiss
                return
        }
        mostRecentIndexPathActioned = indexPath
        animator.preferredCommitStyle = .pop
        if let cell = collection.cellForItem(at: indexPath) as? ArchivedItemCell {
            animator.addCompletion {
                item.tryPreview(in: self, from: cell, forceFullscreen: false)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = item(for: indexPath) else {
            return nil
        }
        
        mostRecentIndexPathActioned = indexPath

        if item.flags.contains(.needsUnlock) {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
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
        
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: {
            return item.previewableTypeItem?.quickLook()
        }, actionProvider: { [weak self] _ in
            return self?.createShortcutActions(for: item, mainView: true, indexPath: indexPath)
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

    func createShortcutActions(for item: ArchivedItem, mainView: Bool, indexPath: IndexPath) -> UIMenu? {
        
        func makeAction(title: String, callback: @escaping () -> Void, style: UIAction.Attributes, iconName: String?) -> UIAction {
            let a = UIAction(title: title) { _ in callback() }
            a.attributes = style
            if let iconName = iconName {
                a.image = UIImage(systemName: iconName)
            }
            return a
        }
        
        var children = [UIMenuElement]()
        
        if mainView && item.canOpen {
            children.append(makeAction(title: "Open", callback: { [weak self] in
                self?.mostRecentIndexPathActioned = indexPath
                item.tryOpen(in: nil) { _ in }
            }, style: [], iconName: "arrow.up.doc"))
        }

        var topElements = mainView ? [
            makeAction(title: "Info Panel", callback: { [weak self] in
                self?.mostRecentIndexPathActioned = indexPath
                self?.performSegue(withIdentifier: "showDetail", sender: item)
            }, style: [], iconName: "list.bullet.below.rectangle")
        ] : [UIAction]()
        
        topElements.append(contentsOf: [
            makeAction(title: "Move to Top", callback: { [weak self] in
                self?.mostRecentIndexPathActioned = indexPath
                Model.sendToTop(items: [item])
            }, style: [], iconName: "arrow.turn.left.up"),
            
            makeAction(title: "Copy to Clipboard", callback: { [weak self] in
                self?.mostRecentIndexPathActioned = indexPath
                item.copyToPasteboard()
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(notification: .announcement, argument: "Copied.")
                }
            }, style: [], iconName: "doc.on.doc")
        ])

        let topHolder = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: topElements)
        children.append(topHolder)

        children.append(makeAction(title: "Duplicate", callback: { [weak self] in
            self?.mostRecentIndexPathActioned = indexPath
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
                            self?.mostRecentIndexPathActioned = indexPath
                            self?.passwordUpdate(nil, hint: nil, for: item)
                        }
                    }
                }, style: [], iconName: "lock.slash"))
            } else {
                children.append(makeAction(title: "Add Lock", callback: {
                    item.lock { [weak self] passwordData, passwordHint in
                        if let d = passwordData {
                            self?.mostRecentIndexPathActioned = indexPath
                            self?.passwordUpdate(d, hint: passwordHint, for: item)
                        }
                    }
                }, style: [], iconName: "lock"))
            }
        }

        children.append(makeAction(title: "Siri Shortcuts", callback: { [weak self] in
            if let s = self, let cell = s.collection.cellForItem(at: indexPath) {
                if let detail = s.currentDetailView {
                    detail.performSegue(withIdentifier: "toSiriShortcuts", sender: nil)
                } else {
                    s.dismissAnyPopOver {
                        s.performSegue(withIdentifier: "toSiriShortcuts", sender: cell)
                    }
                }
            }
        }, style: [], iconName: "mic"))
        
        if CloudManager.syncSwitchedOn {
            if item.shareMode == .none {
                children.append(makeAction(title: "Collaborate", callback: { [weak self] in
                    guard let s = self else { return }
                    s.dismissAnyPopOver {
                        s.addInvites(to: item, at: indexPath)
                    }
                }, style: [], iconName: "person.crop.circle.badge.plus"))
                
            } else {
                children.append(makeAction(title: "Collaboration…", callback: { [weak self] in
                    guard let s = self else { return }
                    s.dismissAnyPopOver {
                        if item.isPrivateShareWithOnlyOwner {
                            s.shareOptionsPrivate(for: item, at: indexPath)
                        } else if item.isShareWithOnlyOwner {
                            s.shareOptionsPublic(for: item, at: indexPath)
                        } else {
                            s.editInvites(in: item, at: indexPath)
                        }
                    }
                }, style: [], iconName: "person.crop.circle.fill.badge.checkmark"))
            }
        }

        if let m = item.mostRelevantTypeItem {
            children.append(makeAction(title: "Share", callback: { [weak self] in
                guard let s = self, let cell = s.collection.cellForItem(at: indexPath) else {
                    return
                }
                
                s.dismissAnyPopOver {
                    s.mostRecentIndexPathActioned = indexPath
                    let a = UIActivityViewController(activityItems: [m.sharingActivitySource], applicationActivities: nil)
                    s.present(a, animated: true)
                    if let p = a.popoverPresentationController {
                        p.sourceView = cell
                        p.sourceRect = cell.bounds.insetBy(dx: cell.bounds.width * 0.2, dy: cell.bounds.height * 0.2)
                    }
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
        let deleteHolder = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: [deleteMenu])
        children.append(deleteHolder)
        
        return UIMenu(title: "", image: nil, identifier: nil, options: [], children: children)
    }
    
    func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return previewForContextMenu(of: configuration)
    }
    
    func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        if UIAccessibility.isVoiceOverRunning,
            let indexPath = configuration.identifier as? IndexPath,
            let cell = collectionView.cellForItem(at: indexPath) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                UIAccessibility.post(notification: .layoutChanged, argument: cell)
            }
        }
        return previewForContextMenu(of: configuration)
    }
    
    private func previewForContextMenu(of configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        if let indexPath = configuration.identifier as? IndexPath,
           let cell = collection.cellForItem(at: indexPath) as? ArchivedItemCell {
            mostRecentIndexPathActioned = indexPath
            return cell.targetedPreviewItem
        }
        return nil
    }
        
    private func createLayout(width: CGFloat, columns: Int, spacing: CGFloat, fixedwidth: CGFloat? = nil, fixedHeight: CGFloat? = nil) -> UICollectionViewCompositionalLayout {
        let itemWidth, itemHeight: NSCollectionLayoutDimension

        let columnCount = CGFloat(columns)
        let extras = spacing * (columnCount - 1)
        let side = ((width - extras) / columnCount).rounded(.down)
        view.window?.windowScene?.session.userInfo?["ItemSide"] = side

        if let fixedwidth = fixedwidth {
            itemWidth = .absolute(fixedwidth)
        } else {
            itemWidth = .fractionalHeight(1)
        }

        if let fixedHeight = fixedHeight {
            itemHeight = .absolute(fixedHeight)
        } else {
            itemHeight = .absolute(side)
        }
        
        let itemSize = NSCollectionLayoutSize(widthDimension: itemWidth, heightDimension: .fractionalHeight(1))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupsSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: itemHeight)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupsSize, subitem: item, count: columns)
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing

        switch filter.groupingMode {
        case .byLabel:
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: spacing + spacing, bottom: spacing * 2, trailing: spacing + spacing)

            let sectionTitleHeight = UIFont.preferredFont(forTextStyle: LabelSectionTitle.titleStyle).lineHeight + 20
            let sectionTitleSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(sectionTitleHeight))
            let sectionTitle = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: sectionTitleSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .topLeading)
            section.boundarySupplementaryItems = [sectionTitle]
            
            let sectionBackground = NSCollectionLayoutDecorationItem.background(elementKind: "sectionBackground")
            sectionBackground.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: spacing, bottom: spacing, trailing: spacing)
            section.decorationItems = [sectionBackground]
        case .flat:
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: spacing, bottom: spacing, trailing: spacing)
        }
        
        let layout = UICollectionViewCompositionalLayout(section: section)
        layout.register(RoundedBackground.self, forDecorationViewOfKind: "sectionBackground")
        return layout
    }
    
    private var lastLayoutProcessed: CGFloat = 0
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        let insets = view.safeAreaInsets
        let bounds = view.bounds
        let width = bounds.size.width - insets.left - insets.right
        let wideMode = PersistedOptions.wideMode
        let forceTwoColumn = PersistedOptions.forceTwoColumnPreference
        
        let key = width + (wideMode ? 1 : 0) + (forceTwoColumn ? 1 : 0)
        if lastLayoutProcessed == key {
            log("Handlesize not needed")
            return
        }

        if wideMode {
            if width >= 768 {
                collection.collectionViewLayout = createLayout(width: width, columns: 2, spacing: 8, fixedHeight: 80)
            } else {
                collection.collectionViewLayout = createLayout(width: width, columns: 1, spacing: 8, fixedHeight: 80)
            }
        } else {
            if width <= 320 && !forceTwoColumn {
                collection.collectionViewLayout = createLayout(width: width, columns: 1, spacing: 10, fixedwidth: 300, fixedHeight: 200)
            } else if width >= 1366 {
                collection.collectionViewLayout = createLayout(width: width, columns: 5, spacing: 10)
            } else if width > 980 {
                collection.collectionViewLayout = createLayout(width: width, columns: 4, spacing: 10)
            } else if width > 438 {
                collection.collectionViewLayout = createLayout(width: width, columns: 3, spacing: 8)
            } else {
                collection.collectionViewLayout = createLayout(width: width, columns: 2, spacing: 6)
            }
        }
        
        lastLayoutProcessed = key
        
        log("Handlesize ran for: \(width)")

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

	@IBAction private func deleteButtonSelected(_ sender: UIBarButtonItem) {
        let candidates = selectedItems
        guard !candidates.isEmpty else { return }

		let a = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
		let msg = candidates.count > 1 ? "Delete \(candidates.count) Items" : "Delete Item"
		a.addAction(UIAlertAction(title: msg, style: .destructive) { _ in
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
        let candidates = selectedItems
        guard !candidates.isEmpty else { return }

        let candidateSet = Set(candidates)
		let itemsToDelete = Model.drops.filter { candidateSet.contains($0) }
		if !itemsToDelete.isEmpty {
            setEditing(false, animated: true)
			Model.delete(items: itemsToDelete)
		}
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

    private var currentPreviewView: GladysPreviewController? {
        return firstPresentedNavigationController?.viewControllers.first as? GladysPreviewController
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
    
    private func dismissAnyPopOver(completion: (() -> Void)? = nil) {
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

	func dismissAnyPopOverOrModal(completion: (() -> Void)? = nil) {
		dismissAnyPopOver {
			if let p = self.navigationItem.searchController?.presentedViewController ?? self.navigationController?.presentedViewController {
				p.dismiss(animated: true) {
					completion?()
				}
			} else {
				completion?()
			}
		}
	}

    @objc private func itemIngested(_ notification: Notification) {
        if let item = notification.object as? ArchivedItem,
           let firstIdentifier = dataSource.snapshot().itemIdentifiers.first(where: { $0.uuid == item.uuid }),
           let indexPath = dataSource.indexPath(for: firstIdentifier) {
            
            mostRecentIndexPathActioned = indexPath
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

		if andLabels {
			filter.disableAllLabels()
			updateLabelIcon()
		}
	}

    @objc private func highlightItem(_ notification: Notification) {
        guard let request = notification.object as? HighlightRequest, let uuid = UUID(uuidString: request.uuid) else { return }
        if filter.filteredDrops.contains(where: { $0.uuid == uuid }) {
			dismissAnyPopOverOrModal {
                self.highlightItem(with: uuid, andOpen: request.open, andPreview: request.preview, focusOnChild: request.focusOnChildUuid)
			}
        } else if Model.firstIndexOfItem(with: request.uuid) != nil {
            self.resetSearch(andLabels: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.highlightItem(with: uuid, andOpen: request.open, andPreview: request.preview, focusOnChild: request.focusOnChildUuid)
            }
		}
	}
    
    private func highlightItem(with uuid: UUID, andOpen: Bool, andPreview: Bool, focusOnChild childUuid: String?) {
        guard let firstIdentifier = dataSource.snapshot().itemIdentifiers.first(where: { $0.uuid == uuid }),
              let ip = dataSource.indexPath(for: firstIdentifier)
        else { return }
        
        collection.isUserInteractionEnabled = false
        
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
    
	func willDismissSearchController(_ searchController: UISearchController) {
		resetSearch(andLabels: false)
	}

	private var searchTimer: PopTimer!

	func updateSearchResults(for searchController: UISearchController) {
		searchTimer.push()
	}

    @objc private func reloadExistingItems(_ notification: Notification) {
        let uuids = filter.filteredDrops.map { $0.uuid }
        lastLayoutProcessed = 0
        updateDataSource(reloading: Set(uuids))
    }
    
	func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		let t = (controller.presentedViewController as? UINavigationController)?.topViewController
		if t is LabelSelector || t is LabelEditorController || t is SiriShortcutsViewController {
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
    
    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        if collectionView.hasActiveDrop && Singleton.shared.componentDropActiveFromDetailView == nil {
            return false
        }

        if let item = item(for: indexPath) {
            return !item.shouldDisplayLoading
        }
        return false
    }
    
    private var selectingGestureActive = false
    
    func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        selectingGestureActive = true
        if !isEditing {
            setEditing(true, animated: true)
        }
    }
    
    func collectionViewDidEndMultipleSelectionInteraction(_ collectionView: UICollectionView) {
        selectingGestureActive = false
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
        activity.userInfo = [kGladysMainViewLabelList: filter.enabledLabelsForTitles,
                             kGladysMainViewSearchText: filter.text ?? "",
                             kGladysMainViewDisplayMode: filter.groupingMode.rawValue]
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

    private func shareOptionsPrivate(for item: ArchivedItem, at indexPath: IndexPath) {
        let a = UIAlertController(title: "No Participants", message: "This item is shared privately, but has no participants yet. You can edit options to make it public, invite more people, or stop sharing it.", preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "Options", style: .default) { [weak self] _ in
            self?.editInvites(in: item, at: indexPath)
        })
        a.addAction(UIAlertAction(title: "Stop Sharing", style: .destructive) { _ in
            CloudManager.deleteShare(item) { _ in }
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(a, animated: true)
        if let p = a.popoverPresentationController, let cell = collection.cellForItem(at: indexPath) {
            p.sourceView = cell
            p.sourceRect = cell.bounds
        }
    }

    private func shareOptionsPublic(for item: ArchivedItem, at indexPath: IndexPath) {
        let a = UIAlertController(title: "No Participants", message: "This item is shared publicly, but has no participants yet. You can edit options to make it private and invite people, or stop sharing it.", preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "Make Private", style: .default) { [weak self] _ in
            self?.editInvites(in: item, at: indexPath)
        })
        a.addAction(UIAlertAction(title: "Stop Sharing", style: .destructive) { _ in
            CloudManager.deleteShare(item) { _ in }
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(a, animated: true)
        if let p = a.popoverPresentationController, let cell = collection.cellForItem(at: indexPath) {
            p.sourceView = cell
            p.sourceRect = cell.bounds
        }
    }

    private func addInvites(to item: ArchivedItem, at indexPath: IndexPath) {
        guard let rootRecord = item.cloudKitRecord else { return }
        let cloudSharingController = UICloudSharingController { _, completion in
            CloudManager.share(item: item, rootRecord: rootRecord, completion: completion)
        }
        presentCloudController(cloudSharingController, for: item, at: indexPath)
    }

    private func editInvites(in item: ArchivedItem, at indexPath: IndexPath) {
        guard let shareRecord = item.cloudKitShareRecord else { return }
        let cloudSharingController = UICloudSharingController(share: shareRecord, container: CloudManager.container)
        presentCloudController(cloudSharingController, for: item, at: indexPath)
    }

    private func presentCloudController(_ cloudSharingController: UICloudSharingController, for item: ArchivedItem, at indexPath: IndexPath) {
        itemToBeShared = item
        cloudSharingController.delegate = self
        cloudSharingController.view.tintColor = view.tintColor
        present(cloudSharingController, animated: true)
        if let p = cloudSharingController.popoverPresentationController, let cell = collection.cellForItem(at: indexPath) {
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
