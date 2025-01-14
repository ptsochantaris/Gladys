import GladysCommon
import GladysUI
import GladysUIKit
import Lista
import PopTimer
import UIKit

extension ItemIdentifier: @retroactive @unchecked Sendable {}
extension SectionIdentifier: @retroactive @unchecked Sendable {}

final class ViewController: GladysViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching,
    UISearchControllerDelegate, UISearchResultsUpdating, UICollectionViewDropDelegate, UICollectionViewDragDelegate,
    UIPopoverPresentationControllerDelegate, FilterDelegate, HighlightListener {
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

    var filter: Filter! {
        didSet {
            if isViewLoaded {
                filterChanged()
            }
        }
    }

    private func filterChanged() {
        if let search = filter.text, search.isPopulated, let sc = navigationItem.searchController {
            sc.searchBar.text = search
            searchTimer.abort()
            updateSearchResults(for: sc)
        }
        updateTitle()
    }

    /////////////////////////////

    private var dragModeReverse = false

    private var highlightRegistration: HighlightRequest.Registration?

    override var title: String? {
        didSet {
            updateTitle()
        }
    }

    private func updateTitle() {
        guard let scene = viewIfLoaded?.window?.windowScene else {
            return
        }

        guard let filter else {
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
            dragModePanel.transform = CGAffineTransform(translationX: 0, y: -44)
            UIView.animate(withDuration: 0.1) {
                self.dragModePanel.alpha = 1
                self.dragModePanel.transform = .identity
            }
        }
    }

    func modelFilterContextChanged(_: Filter, animate: Bool) {
        updateDataSource(animated: animate)
        updateLabelIcon()
        updateEmptyView()
    }

    @IBAction private func dragModeButtonSelected(_: UIButton) {
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

    func collectionView(_: UICollectionView, dropSessionDidExit session: UIDropSession) {
        if PersistedOptions.showCopyMoveSwitchSelector {
            if session.localDragSession?.localContext as? String != "typeItem" {
                showDragModeOverlay(true)
            }
        }

        Component.droppedIds.removeAll()
    }

    func collectionView(_: UICollectionView, dragSessionDidEnd _: UIDragSession) {
        showDragModeOverlay(false)

        let items = Component.droppedIds.compactMap { DropStore.item(uuid: $0) }
        if items.isPopulated {
            if dragModeMove {
                Model.delete(items: items)
            }
        }

        Component.droppedIds.removeAll()
    }

    func collectionView(_: UICollectionView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        Component.droppedIds.removeAll()
        if let item = item(for: indexPath), !item.flags.contains(.needsUnlock) {
            return [item.dragItem]
        }
        return []
    }

    func collectionView(_: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point _: CGPoint) -> [UIDragItem] {
        guard let item = item(for: indexPath) else { return [] }
        let dragItem = item.dragItem
        if session.localContext as? String == "typeItem" || session.items.contains(dragItem) || item.flags.contains(.needsUnlock) {
            return []
        } else {
            return [dragItem]
        }
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

        if let cell = cell as? ArchivedItemCell, let uuid = dataSource.itemIdentifier(for: indexPath)?.uuid {
            configureCell(cell, identifier: uuid)
        }
    }

    func collectionView(_: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt _: IndexPath) {
        (cell as? ArchivedItemCell)?.didEndDisplaying()
    }

    private func path(at point: CGPoint) -> IndexPath {
        var rects = [Int: CGRect]()
        let visibleCells = collection.visibleCells
        if visibleCells.isEmpty {
            return IndexPath(item: 0, section: 0)
        }
        var maxSection = 0
        for cell in visibleCells {
            guard let indexPath = collection.indexPath(for: cell) else {
                continue
            }
            let wideFrame = CGRect(x: 0, y: cell.frame.origin.y, width: collection.bounds.width, height: cell.frame.height)
            if let existingRect = rects[indexPath.section] {
                rects[indexPath.section] = existingRect.union(wideFrame)
            } else {
                rects[indexPath.section] = wideFrame
            }
            maxSection = max(maxSection, indexPath.section)
        }
        if let entry = rects.first(where: { $0.value.contains(point) }) {
            let itemCount = collection.numberOfItems(inSection: entry.key)
            return IndexPath(item: itemCount, section: entry.key)
        }
        let itemCount = collection.numberOfItems(inSection: maxSection)
        return IndexPath(item: itemCount, section: maxSection)
    }

    private func insert(item: ArchivedItem, at destinationIndexPath: IndexPath, offset: Int = 0) {
        if let uuid = dataSource.itemIdentifier(for: destinationIndexPath)?.uuid, let index = DropStore.indexOfItem(with: uuid) {
            DropStore.insert(drop: item, at: index + offset)
        } else {
            DropStore.append(drop: item)
        }
    }

    private enum PostDropAction: Int {
        case none, updateUI, save
        func supercedes(action: PostDropAction) -> Bool {
            rawValue > action.rawValue
        }
    }

    private func gladysToGladysDrop(existingItem: ArchivedItem, sourceIndexPath: IndexPath?, to destinationIndexPath: IndexPath) -> PostDropAction {
        Component.droppedIds.remove(existingItem.uuid) // do not count this as an external drop
        guard let modelSourceIndex = DropStore.indexOfItem(with: existingItem.uuid) else {
            return .none
        }

        let destinationSectionIndex = IndexPath(item: 0, section: destinationIndexPath.section)
        DropStore.removeDrop(at: modelSourceIndex)

        switch filter.groupingMode {
        case .byLabel:
            if let sourceIndexPath,
               let destinationSectionLabel = dataSource.itemIdentifier(for: destinationSectionIndex)?.label?.function,
               let sourceSectionLabel = dataSource.itemIdentifier(for: sourceIndexPath)?.label?.function,
               sourceSectionLabel != destinationSectionLabel {
                // drag between sections in same window
                insert(item: existingItem, at: destinationIndexPath)

                existingItem.labels.removeAll { $0 == sourceSectionLabel.displayText }
                if case let .userLabel(text) = destinationSectionLabel, !existingItem.labels.contains(text) {
                    existingItem.labels.append(text)
                }
                existingItem.markUpdated()
                return .save

            } else if sourceIndexPath != nil {
                // drag inside same section
                insert(item: existingItem, at: destinationIndexPath)
                return .save

            } else if let destinationSectionLabel = dataSource.itemIdentifier(for: destinationSectionIndex)?.label?.function {
                // drag into section from another Gladys window
                insert(item: existingItem, at: destinationIndexPath)

                if case let .userLabel(text) = destinationSectionLabel, !existingItem.labels.contains(text) {
                    existingItem.labels.append(text)
                    existingItem.markUpdated()
                }
                return .save
            }

        case .flat:
            // gladys-to-gladys
            // also covers case of another window
            insert(item: existingItem, at: destinationIndexPath)
            if !PersistedOptions.dontAutoLabelNewItems, filter.isFilteringLabels, existingItem.labels != filter.enabledLabelsForItems {
                existingItem.labels = Array(Set(existingItem.labels).union(filter.enabledLabelsForItems))
                existingItem.postModified()
                existingItem.markUpdated()
            }
            return .save
        }

        log("Warning: Unhandled local drop scenario")
        return .none
    }

    private func externalDrop(dragItem: UIDragItem, to destinationIndexPath: IndexPath) -> PostDropAction {
        var result = PostDropAction.none

        let importer = DataImporter(itemProvider: dragItem.itemProvider)
        for newItem in ArchivedItem.importData(providers: [importer], overrides: nil) {
            switch filter.groupingMode {
            case .byLabel:
                let destinationSectionIndex = IndexPath(item: 0, section: destinationIndexPath.section)
                if let destinationSectionLabel = dataSource.itemIdentifier(for: destinationSectionIndex)?.label?.function, case let .userLabel(text) = destinationSectionLabel {
                    newItem.labels.append(text)
                }
            case .flat:
                if !PersistedOptions.dontAutoLabelNewItems, filter.isFilteringLabels {
                    newItem.labels = filter.enabledLabelsForItems
                }
            }
            insert(item: newItem, at: destinationIndexPath)
            result = .updateUI // ingest will take care of saving - do not save here, dangerous
        }

        if result == .none {
            log("Warning: Unhandled external drop scenario")
        }
        return result
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        coordinator.session.progressIndicatorStyle = .none

        let destinationIndexPath = coordinator.destinationIndexPath ?? path(at: coordinator.session.location(in: collectionView))

        var action = PostDropAction.none

        for coordinatorItem in coordinator.items {
            let dragItem = coordinatorItem.dragItem
            let newAction: PostDropAction = if let existingItem = dragItem.localObject as? ArchivedItem {
                gladysToGladysDrop(existingItem: existingItem, sourceIndexPath: coordinatorItem.sourceIndexPath, to: destinationIndexPath)
            } else {
                externalDrop(dragItem: dragItem, to: destinationIndexPath)
            }
            if newAction.supercedes(action: action) {
                action = newAction
            }

            coordinator.drop(dragItem, toItemAt: destinationIndexPath)
            filter.update(signalUpdate: .animated)
            mostRecentIndexPathActioned = destinationIndexPath
        }

        switch action {
        case .none:
            break
        case .updateUI:
            focusInitialAccessibilityElement()
            updateEmptyView()
        case .save:
            Task {
                await Model.save()
            }
        }

        collection.isAccessibilityElement = false
    }

    func collectionView(_: UICollectionView, canHandle _: UIDropSession) -> Bool {
        true
    }

    private func countInserts(in session: UIDropSession) -> Int {
        session.items.reduce(0) { count, item in
            if item.localObject == nil {
                return count + 1
            }
            return count
        }
    }

    func collectionView(_: UICollectionView, dropSessionDidEnter session: UIDropSession) {
        showDragModeOverlay(false)
        Task {
            await resetForDragEntry(session: session)
        }
    }

    func collectionView(_: UICollectionView, dropSessionDidEnd _: UIDropSession) {
        showDragModeOverlay(false)
    }

    func resetForDragEntry(session: UIDropSession) async {
        if currentPreferencesView != nil && !session.hasItemsConforming(toTypeIdentifiers: [GladysFileUTI, "public.zip-archive"]) {
            await dismissAnyPopOver()
        } else if (Singleton.shared.componentDropActiveFromDetailView == nil && currentDetailView != nil) || currentLabelSelector != nil {
            await dismissAnyPopOver()
        }
    }

    func collectionView(_: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
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
            if let p = segue.destination.popoverPresentationController {
                p.delegate = self
            }

        case "showDetail":
            guard let item = sender as? ArchivedItem,
                  let indexPath = mostRecentIndexPathActioned,
                  let n = segue.destination as? UINavigationController,
                  let d = n.topViewController as? DetailController,
                  let p = n.popoverPresentationController,
                  let cell = collection.cellForItem(at: indexPath) as? ArchivedItemCell,
                  let myNavView = navigationController?.view
            else { return }

            d.sourceIndexPath = indexPath
            d.item = item
            cell.skipFade = true

            #if !os(visionOS)
                if let sheet = n.popoverPresentationController?.adaptiveSheetPresentationController {
                    sheet.largestUndimmedDetentIdentifier = .none
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                    sheet.prefersEdgeAttachedInCompactHeight = true
                    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = false
                    sheet.detents = [.custom { _ in
                        n.preferredContentSize.height
                    }]
                }
            #endif
            p.permittedArrowDirections = [.left, .right, .down]
            p.sourceView = myNavView
            p.sourceRect = cell.convert(cell.bounds.insetBy(dx: cell.bounds.width * 0.1, dy: cell.bounds.height * 0.1), to: myNavView)
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
            e.selectedItems = selectedItems.map(\.uuid)
            e.endCallback = { [weak self] hasChanges in
                guard let self else { return }
                if hasChanges {
                    setEditing(false, animated: true)
                }
            }

        default: break
        }
    }

    func collectionView(_: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let style: ArchivedItemWrapper.Style = PersistedOptions.wideMode ? .wide : .square
        let compact = cellSize.isCompact
        let expectedCellSize = CGSize(width: cellSize.width - ArchivedItemWrapper.labelPadding(compact: compact) * 2, height: cellSize.height)

        for ip in indexPaths {
            if let uuid = dataSource.itemIdentifier(for: ip)?.uuid,
               presentationInfoCache[uuid] == nil,
               let item = DropStore.item(uuid: uuid) {
                log("Prefetching presentation info for \(uuid)")
                Task {
                    await item.createPresentationInfo(style: style, expectedSize: expectedCellSize)
                }
            }
        }
    }

    private func trackCellForAWhile(_ cell: UICollectionViewCell, for popOver: UIPopoverPresentationController, in container: UIView) {
        var observation: NSKeyValueObservation?
        observation = cell.observe(\.center, options: .new) { strongCell, _ in
            Task { @MainActor in
                let cellRect = strongCell.convert(cell.bounds.insetBy(dx: 6, dy: 6), to: container)
                popOver.sourceRect = cellRect
                popOver.containerView?.setNeedsLayout()
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
                    popOver.containerView?.layoutIfNeeded()
                }
                observation = nil
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 1000 * NSEC_PER_MSEC)
            if observation != nil { // keep it around
                observation = nil
            }
        }
    }

    private func item(for indexPath: IndexPath) -> ArchivedItem? {
        if let uuid = dataSource.itemIdentifier(for: indexPath)?.uuid {
            return DropStore.item(uuid: uuid)
        }
        return nil
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if collectionView.hasActiveDrop, Singleton.shared.componentDropActiveFromDetailView == nil { return false }
        guard let item = item(for: indexPath) else {
            return false
        }
        return !item.status.shouldDisplayLoading
    }

    func collectionView(_: UICollectionView, didDeselectItemAt _: IndexPath) {
        updateUI()
    }

    func collectionView(_: UICollectionView, sceneActivationConfigurationForItemAt indexPath: IndexPath, point _: CGPoint) -> UIWindowScene.ActivationConfiguration? {
        guard let cell = collection.cellForItem(at: indexPath) as? ArchivedItemCell,
              let item = cell.archivedDropItem else {
            return nil
        }

        mostRecentIndexPathActioned = indexPath
        let activity = NSUserActivity(activityType: kGladysQuicklookActivity)
        ArchivedItem.updateUserActivity(activity, from: item, child: nil, titled: "Quick look")

        let options = UIWindowScene.ActivationRequestOptions()
        options.placement = UIWindowSceneProminentPlacement.prominent()
        return UIWindowScene.ActivationConfiguration(userActivity: activity, options: options, preview: cell.targetedPreviewItem)
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
            Task {
                if let success = await item.unlock(label: "Unlock Item", action: "Unlock"), success {
                    item.flags.remove(.needsUnlock)
                    item.postModified()
                }
            }
            return
        }

        mostRecentIndexPathActioned = indexPath

        Task {
            await dismissAnyPopOverOrModal()

            switch PersistedOptions.actionOnTap {
            case .infoPanel:
                segue("showDetail", sender: item)

            case .copy:
                item.copyToPasteboard()
                await genericAlert(title: nil, message: "Copied to clipboard", buttonTitle: nil)

            case .open:
                let success = await item.tryOpen(in: nil)
                if !success {
                    segue("showDetail", sender: item)
                }

            case .preview:
                let cell = collectionView.cellForItem(at: indexPath) as? ArchivedItemCell
                if let presenter = view.window?.alertPresenter, !item.tryPreview(in: presenter, from: cell) {
                    segue("showDetail", sender: item)
                }

            case .none:
                break
            }
        }
    }

    private var focusedItem: UIFocusItem? {
        view.window?.windowScene?.focusSystem?.focusedItem
    }

    @objc private func quickLookFocusedItem() {
        if let focusedCell = focusedItem as? ArchivedItemCell, let item = focusedCell.archivedDropItem {
            _ = item.tryPreview(in: self, from: focusedCell)
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            navigationItem.largeTitleDisplayMode = .never
            navigationItem.largeTitleDisplayMode = .automatic
            pasteButton.accessibilityLabel = "Paste from clipboard"
            settingsButton.accessibilityLabel = "Settings"
            shareButton.accessibilityLabel = "Share"

            dragModePanel.translatesAutoresizingMaskIntoConstraints = false
            dragModePanel.layer.shadowColor = UIColor.label.cgColor
            dragModePanel.layer.shadowOffset = CGSize(width: 0, height: 1)
            dragModePanel.layer.shadowOpacity = 0.3
            dragModePanel.layer.shadowRadius = 2
            dragModePanel.layer.cornerRadius = 20
            dragModePanel.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]
            dragModePanel.alpha = 0
        }
    }

    private func updateDataSource(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<SectionIdentifier, ItemIdentifier>()

        switch filter.groupingMode {
        case .byLabel:
            let toggles = filter.enabledToggles
            var labelLookups = [Filter.Toggle.Function: Lista<UUID>]()
            for item in filter.filteredDrops {
                if item.isRecentlyAdded {
                    if let list = labelLookups[.recentlyAddedItems] {
                        list.append(item.uuid)
                    } else {
                        labelLookups[.recentlyAddedItems] = Lista(value: item.uuid)
                    }
                }
                if item.labels.isEmpty {
                    if let list = labelLookups[.unlabeledItems] {
                        list.append(item.uuid)
                    } else {
                        labelLookups[.unlabeledItems] = Lista(value: item.uuid)
                    }
                } else {
                    for text in item.labels {
                        let function = Filter.Toggle.Function.userLabel(text)
                        if let list = labelLookups[function] {
                            list.append(item.uuid)
                        } else {
                            labelLookups[function] = Lista(value: item.uuid)
                        }
                    }
                }
            }

            for toggle in toggles {
                if let sectionItems = labelLookups[toggle.function]?.uniqued.map({ ItemIdentifier(label: toggle, uuid: $0) }), sectionItems.isPopulated {
                    let sectionIdentifier = SectionIdentifier(label: toggle)
                    snapshot.appendSections([sectionIdentifier])
                    if toggle.currentDisplayMode != .collapsed {
                        snapshot.appendItems(sectionItems, toSection: sectionIdentifier)
                    }
                }
            }

            for subview in collection.subviews {
                (subview as? LabelSectionTitle)?.reset()
            }

        case .flat:
            let section = SectionIdentifier(label: nil)
            snapshot.appendSections([section])
            let identifiers = filter.filteredDrops.map { ItemIdentifier(label: nil, uuid: $0.uuid) }
            snapshot.appendItems(identifiers, toSection: section)
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func anyPath(in frame: CGRect) -> IndexPath? {
        if let cell = collection.visibleCells.first(where: { frame.contains($0.frame) }) {
            return collection.indexPath(for: cell)
        }
        return nil
    }

    private var dataSource: UICollectionViewDiffableDataSource<SectionIdentifier, ItemIdentifier>!

    private func setupNotificationHandlers() {
        notifications(for: .LabelSelectionChanged) { [weak self] _ in
            guard let self else { return }
            filter.update(signalUpdate: .animated, forceAnnounce: filter.groupingMode == .byLabel) // as there may be new label sections to show even if the items don't change
            updateLabelIcon()
            userActivity?.needsSave = true
        }

        notifications(for: .ItemCollectionNeedsDisplay) { [weak self] object in
            guard let self else { return }
            if object as? Bool == true || object as? UIWindowScene == view.window?.windowScene {
                lastLayoutProcessed = 0
                setupLayout()
                collection.collectionViewLayout.invalidateLayout()
                updateDataSource(animated: false)
                collection.reloadData()
            } else {
                let uuids = filter.filteredDrops.map(\.uuid)
                DropStore.reloadCells(for: Set(uuids))
            }
        }

        notifications(for: .ModelDataUpdated) { [weak self] object in
            await self?._modelDataUpdate(object)
        }

        notifications(for: .CloudManagerStatusChanged) { [weak self] _ in
            await self?.cloudStatusChanged()
        }

        notifications(for: .ReachabilityChanged) { _ in
            guard await CloudManager.syncContextSetting == .wifiOnly, await Reachability.shared.isReachableViaLowCost else {
                return
            }
            do {
                try await CloudManager.opportunisticSyncIfNeeded()
            } catch {
                log("Error in reachability triggered sync: \(error.localizedDescription)")
            }
        }

        notifications(for: .AcceptStarting) { _ in
            await genericAlert(title: "Accepting Share…", message: nil) { [weak self] alert in
                guard let self else { return }
                acceptAlert = alert
            }
        }

        notifications(for: .AcceptEnding) { [weak self] _ in
            guard let self else { return }
            await acceptAlert?.dismiss(animated: true)
            acceptAlert = nil
        }

        notifications(for: .IngestComplete) { [weak self] object in
            if let self,
               let item = object as? ArchivedItem,
               let firstIdentifier = dataSource.snapshot().itemIdentifiers.first(where: { $0.uuid == item.uuid }),
               let indexPath = dataSource.indexPath(for: firstIdentifier) {
                mostRecentIndexPathActioned = indexPath
                if currentDetailView == nil {
                    focusInitialAccessibilityElement()
                }
            }

            if !DropStore.processingItems {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }

        // Not using notifications macro because registration needs to be immediate
        highlightRegistration = HighlightRequest.registerListener(listener: self)

        notifications(for: .UIRequest) { [weak self] object in
            guard let self,
                  let request = object as? UIRequest,
                  request.sourceScene == view.window?.windowScene
            else { return }

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

        notifications(for: .DismissPopoversRequest) { [weak self] _ in
            await self?.dismissAnyPopOver()
        }

        notifications(for: .ResetSearchRequest) { [weak self] _ in
            guard let self else { return }
            if searchActive || filter.isFiltering {
                await resetSearch(andLabels: true)
            }
        }

        notifications(for: UIApplication.keyboardWillHideNotification) { [weak self] _ in
            guard let self else { return }
            if presentedViewController != nil {
                return
            }
            if currentDetailView != nil {
                return
            }
            if !filter.isFilteringText {
                await resetSearch(andLabels: false)
            }
        }

        notifications(for: .SectionHeaderTapped) { [weak self] object in
            guard let self, let event = object as? BackgroundSelectionEvent, event.scene == view.window?.windowScene else { return }
            var name = event.name

            if name == nil, let frame = event.frame, let sectionIndexPath = anyPath(in: frame) {
                name = dataSource.itemIdentifier(for: sectionIndexPath)?.label?.function.displayText
            }

            guard let name, let toggle = filter.labelToggles.first(where: { $0.function.displayText == name }) else { return }
            switch toggle.currentDisplayMode {
            case .collapsed:
                filter.setDisplayMode(to: toggle.preferredDisplayMode, for: [name], setAsPreference: false)
            case .full, .scrolling:
                filter.setDisplayMode(to: .collapsed, for: [name], setAsPreference: false)
            }
            updateDataSource(animated: true)
            userActivity?.needsSave = true
        }

        notifications(for: .SectionShowAllTapped) { [weak self] object in
            guard let self, let event = object as? BackgroundSelectionEvent, event.scene == view.window?.windowScene else { return }
            var name = event.name

            if name == nil, let frame = event.frame, let sectionIndexPath = anyPath(in: frame) {
                name = dataSource.itemIdentifier(for: sectionIndexPath)?.label?.function.displayText
            }

            guard let name, let toggle = filter.labelToggles.first(where: { $0.function.displayText == name }) else { return }
            switch toggle.currentDisplayMode {
            case .collapsed, .scrolling:
                filter.setDisplayMode(to: .full, for: [name], setAsPreference: true)
            case .full:
                filter.setDisplayMode(to: .scrolling, for: [name], setAsPreference: true)
            }
            updateDataSource(animated: true)
            userActivity?.needsSave = true
        }
    }

    override func paste(itemProviders: [NSItemProvider]) {
        Model.pasteItems(from: itemProviders.map { DataImporter(itemProvider: $0) }, overrides: nil, currentFilter: filter)
    }

    override func canPaste(_: [NSItemProvider]) -> Bool {
        true
    }

    private func configureCell(_ cell: ArchivedItemCell, identifier: UUID) {
        cell.wideCell = PersistedOptions.wideMode
        cell.lowMemoryMode = lowMemoryMode
        cell.owningViewController = self
        cell.archivedDropItem = DropStore.item(uuid: identifier)
        cell.isEditing = isEditing
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let cellRegistration = UICollectionView.CellRegistration<ArchivedItemCell, ItemIdentifier> { [unowned self] cell, _, identifier in
            configureCell(cell, identifier: identifier.uuid)
        }

        dataSource = UICollectionViewDiffableDataSource<SectionIdentifier, ItemIdentifier>(collectionView: collection) { collectionView, indexPath, sectionItem in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: sectionItem)
        }

        collection.reorderingCadence = .slow
        collection.accessibilityLabel = "Items"
        collection.dragInteractionEnabled = true
        collection.dataSource = dataSource
        collection.contentOffset = .zero
        collection.focusGroupIdentifier = "build.bru.gladys.collection"
        collection.allowsFocus = true
        collection.remembersLastFocusedIndexPath = true

        let headerMenuOptions = [
            UIAction(title: "Collapse All", image: UIImage(systemName: "line.horizontal.3")) { [weak self] _ in
                guard let self else { return }
                filter.setDisplayMode(to: .collapsed, for: nil, setAsPreference: false)
                updateDataSource(animated: true)
            },
            UIAction(title: "Expand All", image: UIImage(systemName: "rectangle.grid.1x2")) { [weak self] _ in
                guard let self else { return }
                filter.setDisplayMode(to: .scrolling, for: nil, setAsPreference: false)
                updateDataSource(animated: true)
            },
            UIAction(title: "Fully Expand All", image: UIImage(systemName: "square")) { [weak self] _ in
                guard let self else { return }
                filter.setDisplayMode(to: .full, for: nil, setAsPreference: false)
                updateDataSource(animated: true)
            }
        ]

        let headerRegistration = UICollectionView.SupplementaryRegistration<LabelSectionTitle>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] titleView, _, indexPath in
            guard let self else { return }
            let sid = dataSource.sectionIdentifier(for: indexPath.section)
            guard let label = sid?.label else { return }
            titleView.configure(with: label, firstSection: indexPath.section == 0, viewController: self, menuOptions: headerMenuOptions)
        }

        let faderRegistration = UICollectionView.SupplementaryRegistration<ScrollFadeView>(elementKind: "ScrollFadeView") { [weak self] view, _, indexPath in
            guard let self else { return }
            let sid = dataSource.sectionIdentifier(for: indexPath.section)
            guard let label = sid?.label else { return }
            view.configure(with: label, viewController: self)
        }

        dataSource.supplementaryViewProvider = { collectionView, type, indexPath in
            switch type {
            case UICollectionView.elementKindSectionHeader:
                collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
            case "ScrollFadeView":
                collectionView.dequeueConfiguredReusableSupplementary(using: faderRegistration, for: indexPath)
            default:
                fatalError("Unknown supplementary view type requested")
            }
        }

        #if os(visionOS)
            navigationController?.navigationBar.titleTextAttributes = [
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
            navigationController?.navigationBar.largeTitleTextAttributes = [
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
        #else
            navigationController?.navigationBar.titleTextAttributes = [
                .foregroundColor: UIColor.g_colorLightGray
            ]
            navigationController?.navigationBar.largeTitleTextAttributes = [
                .foregroundColor: UIColor.g_colorLightGray
            ]
        #endif

        let searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.returnKeyType = .search
        searchController.searchBar.enablesReturnKeyAutomatically = false
        searchController.searchBar.focusGroupIdentifier = "build.bru.gladys.searchbar"
        searchController.searchBar.isLookToDictateEnabled = true
        navigationItem.searchController = searchController

        searchTimer = PopTimer(timeInterval: 0.4) { [weak searchController, weak self] in
            guard let self, let searchController else { return }
            filter.text = searchController.searchBar.text
            userActivity?.needsSave = true
            updateUI()
        }

        navigationController?.setToolbarHidden(true, animated: false)

        setupNotificationHandlers()

        if filter.isFilteringLabels { // in case we're restored with active labels
            filter.update(signalUpdate: .none)
        }

        UIView.performWithoutAnimation {
            updateUI()
            blurb(Greetings.openLine)
        }

        Task {
            await cloudStatusChanged()
        }

        dismissOnNewWindow = false
        autoConfigureButtons = true

        userActivity = NSUserActivity(activityType: kGladysMainListActivity)
        userActivity?.needsSave = true

        updateDataSource(animated: false)

        let descendingMenu = SortOption.options.map { option -> UIMenuElement in
            UIAction(title: option.descendingTitle, image: option.descendingIcon, identifier: nil) { [weak self] _ in
                guard let self else { return }
                sortRequested(option, ascending: false, button: sortAscendingButton)
            }
        }
        let ascendingMenu = SortOption.options.map { option -> UIMenuElement in
            UIAction(title: option.ascendingTitle, image: option.ascendingIcon, identifier: nil) { [weak self] _ in
                guard let self else { return }
                sortRequested(option, ascending: true, button: sortAscendingButton)
            }
        }
        let menuItems = [
            UIMenu(title: "Ascending", image: UIImage(systemName: "arrow.down"), identifier: nil, options: [.displayInline], children: ascendingMenu),
            UIMenu(title: "Descending", image: UIImage(systemName: "arrow.up"), identifier: nil, options: [.displayInline], children: descendingMenu)
        ]
        let menu = UIMenu(title: "Sort", image: UIImage(systemName: "arrow.up.arrow.down"), identifier: UIMenu.Identifier("sortMenu"), options: [], children: menuItems)
        sortAscendingButton.menu = menu

        filter.delegate = self
        filterChanged()

        updatePasteButton()

        registerForTraitChanges([UITraitActiveAppearance.self]) { [weak self] (_: UITraitEnvironment, _: UITraitCollection) in
            guard let self else { return }
            presentationInfoCache.reset()
            collection.reloadData()
        }
    }

    deinit {
        highlightRegistration?.cancel()
        log("Main VC deinitialised")
    }

    private var acceptAlert: UIAlertController?

    @objc private func refreshControlChanged(_ r: UIRefreshControl) {
        guard r.isRefreshing else { return }
        Task {
            await _refreshControlChanged()
        }
    }

    private func _refreshControlChanged() async {
        let syncing = await CloudManager.syncing
        if !syncing {
            do {
                try await CloudManager.sync(force: true)
            } catch {
                await genericAlert(title: "Sync Error", message: error.localizedDescription)
            }
            lastSyncUpdate()
        }
    }

    private func cloudStatusChanged() async {
        let syncOn = await CloudManager.syncSwitchedOn
        let syncing = await CloudManager.syncing
        let transitioning = await CloudManager.syncTransitioning

        if syncOn && collection.refreshControl == nil {
            let refresh = UIRefreshControl()
            refresh.addTarget(self, action: #selector(refreshControlChanged(_:)), for: .valueChanged)
            collection.refreshControl = refresh
            navigationController?.view.layoutIfNeeded()

        } else if !syncOn && collection.refreshControl != nil {
            collection.refreshControl = nil
        }

        if let r = collection.refreshControl {
            if r.isRefreshing, !syncing {
                r.endRefreshing()
            }
            lastSyncUpdate()
        }

        if syncing || transitioning {
            collection.accessibilityLabel = await CloudManager.makeSyncString()
        } else {
            collection.accessibilityLabel = "Items"
        }
    }

    private func lastSyncUpdate() {
        if let r = collection.refreshControl {
            Task {
                let message = await CloudManager.makeSyncString()
                r.attributedTitle = NSAttributedString(string: message, attributes: [:])
            }
        }
    }

    func scrollViewWillBeginDragging(_: UIScrollView) {
        lastSyncUpdate()
    }

    @IBOutlet private var pasteButton: UIBarButtonItem!

    @IBAction private func pasteSelected(_: UIBarButtonItem) {
        if case .noData = Model.pasteItems(from: UIPasteboard.general.itemProviders.map { DataImporter(itemProvider: $0) }, overrides: nil, currentFilter: filter) {
            Task {
                await genericAlert(title: "Nothing to Paste", message: "There is currently nothing in the clipboard.")
            }
        }
    }

    private var lowMemoryMode = false

    override func didReceiveMemoryWarning() {
        if let collection {
            if UIApplication.shared.applicationState == .background {
                log("Placing UI in background low-memory mode")
                lowMemoryMode = true
                collection.reloadData()
            }
        }
        super.didReceiveMemoryWarning()
    }

    func sceneBackgrounded() {
        lowMemoryMode = true
        if let collection {
            collection.reloadData()
        }
    }

    func sceneForegrounded() {
        lowMemoryMode = false
        if let collection {
            collection.reloadData()
        }
        if emptyView != nil {
            blurb(Greetings.randomGreetLine)
        }
    }

    private func _modelDataUpdate(_ object: Any?) async {
        let oldUUIDs = filter.filteredDrops.map(\.uuid)
        let oldSet = Set(oldUUIDs)

        let previous = filter.enabledToggles
        filter.rebuildLabels()
        let forceAnnounce = previous != filter.enabledToggles
        filter.update(signalUpdate: .animated, forceAnnounce: forceAnnounce)

        let parameters = object as? [AnyHashable: Any]
        if let uuidsToReload = (parameters?["updated"] as? Set<UUID>)?.intersection(oldSet), uuidsToReload.isPopulated {
            DropStore.reloadCells(for: uuidsToReload)
        }

        let newUUIDs = filter.filteredDrops.map(\.uuid)
        let newSet = Set(newUUIDs)

        let removed = oldSet.subtracting(newSet)
        let added = newSet.subtracting(oldSet)

        let removedItems = removed.isPopulated
        let ipsInsered = added.isPopulated
        let ipsMoved = !removedItems && !ipsInsered && oldUUIDs != newUUIDs

        if removedItems || ipsInsered || ipsMoved {
            if !phoneMode, let vc = (currentDetailView ?? currentPreviewView) {
                await vc.dismiss(animated: false)
            }

            if removedItems {
                if filter.filteredDrops.isEmpty {
                    if filter.isFiltering {
                        await resetSearch(andLabels: true)
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

    @objc private func updateUI() {
        if DropStore.dropsAreEmpty {
            editButton.isEnabled = false
            if isEditing {
                setEditing(false, animated: true)
            }
        } else {
            editButton.isEnabled = true
        }

        let filteredDrops = filter.filteredDrops

        if isEditing {
            let selected = Set(selectedItems)
            let selectedCount = selected.count
            let someSelected = selectedCount > 0

            func setItemCountTitle(_ count: Int, _ text: String, colon: Bool) {
                let colonText = colon && collection.bounds.width > 512 ? ":" : ""
                itemsCount.title = "\(count) \(text)\(colonText)"
            }

            let currentItemCount = filteredDrops.count
            let c = someSelected ? selectedCount : currentItemCount
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

            totalSizeLabel.title = "…"
            Task {
                let drops = someSelected ? filteredDrops.filter { selected.contains($0) } : filteredDrops
                let size = await DropStore.sizeForItems(uuids: drops.map(\.uuid))
                let sizeLabel = diskSizeFormatter.string(fromByteCount: size)
                totalSizeLabel.title = sizeLabel
            }
            deleteButton.isEnabled = someSelected
            editLabelsButton.isEnabled = someSelected
            shareButton.isEnabled = someSelected

            if currentItemCount == 0 {
                itemsCount.isEnabled = false
                itemsCount.menu = nil
            } else {
                var actions = [UIAction]()
                if selectedCount < currentItemCount {
                    let selectTitle: String
                    let extra = currentItemCount - selectedCount
                    if extra < currentItemCount {
                        selectTitle = "Select \(extra) More"
                    } else {
                        selectTitle = extra > 1 ? "Select \(extra) Items" : "Select Item"
                    }
                    actions.append(UIAction(title: selectTitle, image: UIImage(systemName: "square.grid.2x2.fill"), handler: { [weak self] _ in
                        guard let self else { return }
                        selectAll(nil)
                    }))
                }
                if selectedCount > 0 {
                    let title = selectedCount > 1 ? "Deselect All Items" : "Deselect Item"
                    actions.append(UIAction(title: title, image: UIImage(systemName: "square.grid.2x2"), handler: { [weak self] _ in
                        guard let self else { return }
                        deselectAll()
                    }))
                }

                itemsCount.menu = UIMenu(title: "", image: nil, identifier: nil, options: [], children: actions)
                itemsCount.isEnabled = true
            }
            currentLabelEditor?.selectedItems = selected.map(\.uuid)
        }

        updateLabelIcon()
        collection.isAccessibilityElement = filteredDrops.isEmpty
        updateEmptyView()
    }

    @IBAction private func shareButtonSelected(_ sender: UIBarButtonItem) {
        let sources = selectedItems.compactMap { $0.mostRelevantTypeItem?.sharingActivitySource }
        if sources.isEmpty { return }
        let a = UIActivityViewController(activityItems: sources, applicationActivities: nil)
        a.completionWithItemsHandler = { [weak self] _, done, _, _ in
            guard let self else { return }
            if done {
                setEditing(false, animated: true)
            }
        }
        present(a, animated: true)
        a.popoverPresentationController?.barButtonItem = sender
    }

    private func sortRequested(_ option: SortOption, ascending: Bool, verifyRange: Bool = true, ignoreSelectedItems: Bool = false, button: UIBarButtonItem) {
        let items = ignoreSelectedItems ? [] : selectedItems
        if items.isPopulated, verifyRange {
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
            filter.update(signalUpdate: .none)
            Task {
                await Model.save()
            }
        }
    }

    private func updateLabelIcon() {
        if filter.isFilteringLabels {
            labelsButton.image = UIImage(systemName: "line.horizontal.3.circle.fill")
            labelsButton.accessibilityValue = "Active"
            title = filter.enabledLabelsForTitles.joined(separator: ", ")
        } else {
            labelsButton.image = UIImage(systemName: "line.horizontal.3.circle")
            labelsButton.accessibilityValue = "Inactive"
            title = "Gladys"
        }
        labelsButton.accessibilityLabel = "Labels"

        let haveDrops = !DropStore.dropsAreEmpty
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

            Task {
                try? await Task.sleep(nanoseconds: 6000 * NSEC_PER_MSEC)
                UIView.animate(withDuration: 1, delay: 0, options: .curveEaseInOut, animations: {
                    l.alpha = 0
                }, completion: { _ in
                    l.removeFromSuperview()
                })
            }
        }
    }

    private var emptyView: UIImageView?

    private func updateEmptyView() {
        let isEmpty = DropStore.dropsAreEmpty
        if isEmpty, emptyView == nil {
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

        } else if let e = emptyView, !isEmpty {
            emptyView = nil
            UIView.animate(animations: {
                e.alpha = 0
            }, completion: { _ in
                e.removeFromSuperview()
            })
        }
    }

    @IBAction private func editButtonSelected(_: UIBarButtonItem) {
        setEditing(!isEditing, animated: true)
    }

    private var selectedItems: [ArchivedItem] {
        (collection.indexPathsForSelectedItems ?? []).compactMap { item(for: $0) }
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

    override func selectAll(_: Any?) {
        // super not called intentionally
        if collection.numberOfSections == 0 {
            return
        }
        if !isEditing {
            isEditing = true
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

    func collectionView(_: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        dragParameters(for: indexPath)
    }

    func collectionView(_: UICollectionView, dropPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        dragParameters(for: indexPath)
    }

    func collectionView(_: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
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
                _ = item.tryPreview(in: self, from: cell, forceFullscreen: false)
            }
        }
    }

    func collectionView(_: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = item(for: indexPath) else {
            return nil
        }

        mostRecentIndexPathActioned = indexPath

        if item.flags.contains(.needsUnlock) {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
                let unlockAction = UIAction(title: "Unlock") { _ in
                    Task {
                        if let success = await item.unlock(label: "Unlock Item", action: "Unlock"), success {
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
            item.previewableTypeItem?.quickLook()
        }, actionProvider: { [weak self] _ in
            self?.createShortcutActions(for: item, mainView: true, indexPath: indexPath)
        })
    }

    private func passwordUpdate(_ newPassword: Data?, hint: String?, for item: ArchivedItem) {
        item.lockPassword = newPassword
        if let hint, hint.isPopulated {
            item.lockHint = hint
        } else {
            item.lockHint = nil
        }
        item.markUpdated()
        item.postModified()
        Task {
            await Model.save()
        }
    }

    func createShortcutActions(for item: ArchivedItem, mainView: Bool, indexPath: IndexPath) -> UIMenu? {
        func makeAction(title: String, callback: @escaping () -> Void, style: UIAction.Attributes, iconName: String?) -> UIAction {
            let a = UIAction(title: title) { _ in callback() }
            a.attributes = style
            if let iconName {
                a.image = UIImage(systemName: iconName)
            }
            return a
        }

        let children = Lista<UIMenuElement>()

        if mainView, item.canOpen {
            children.append(makeAction(title: "Open", callback: { [weak self] in
                guard let self else { return }
                Task {
                    self.mostRecentIndexPathActioned = indexPath
                    await item.tryOpen(in: nil)
                }
            }, style: [], iconName: "arrow.up.doc"))
        }

        var topElements = mainView ? [
            makeAction(title: "Info Panel", callback: { [weak self] in
                guard let self else { return }
                mostRecentIndexPathActioned = indexPath
                segue("showDetail", sender: item)
            }, style: [], iconName: "list.bullet.below.rectangle")
        ] : [UIAction]()

        topElements.append(contentsOf: [
            makeAction(title: "Move to Top", callback: { [weak self] in
                guard let self else { return }
                mostRecentIndexPathActioned = indexPath
                Model.sendToTop(items: [item])
            }, style: [], iconName: "arrow.turn.left.up"),

            makeAction(title: "Copy to Clipboard", callback: { [weak self] in
                guard let self else { return }
                mostRecentIndexPathActioned = indexPath
                item.copyToPasteboard()
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(notification: .announcement, argument: "Copied.")
                }
            }, style: [], iconName: "doc.on.doc")
        ])

        let topHolder = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: topElements)
        children.append(topHolder)

        children.append(makeAction(title: "Duplicate", callback: { [weak self] in
            guard let self else { return }
            mostRecentIndexPathActioned = indexPath
            Model.duplicate(item: item)
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Duplicated.")
            }
        }, style: [], iconName: "arrow.branch"))

        if !item.isImportedShare {
            if item.isLocked {
                children.append(makeAction(title: "Remove Lock", callback: { [weak self] in
                    guard let self else { return }
                    Task { [weak self] in
                        guard let self else { return }
                        if let success = await item.unlock(label: "Remove Lock", action: "Remove"), success {
                            mostRecentIndexPathActioned = indexPath
                            passwordUpdate(nil, hint: nil, for: item)
                        }
                    }
                }, style: [], iconName: "lock.slash"))
            } else {
                children.append(makeAction(title: "Add Lock", callback: { [weak self] in
                    guard let self else { return }
                    Task { [weak self] in
                        guard let self else { return }
                        let (passwordData, passwordHint) = await item.lock()
                        if let passwordData {
                            mostRecentIndexPathActioned = indexPath
                            passwordUpdate(passwordData, hint: passwordHint, for: item)
                        }
                    }
                }, style: [], iconName: "lock"))
            }
        }

        if item.cloudKitRecord != nil {
            if item.shareMode == .none {
                children.append(makeAction(title: "Collaborate", callback: { [weak self] in
                    Task {
                        await self?.addInvites(to: item, at: indexPath)
                    }
                }, style: [], iconName: "person.crop.circle.badge.plus"))

            } else {
                children.append(makeAction(title: "Collaboration…", callback: { [weak self] in
                    Task {
                        await self?.editInvites(in: item, at: indexPath)
                    }
                }, style: [], iconName: "person.crop.circle.fill.badge.checkmark"))
            }
        }

        if let m = item.mostRelevantTypeItem {
            children.append(makeAction(title: "Share", callback: { [weak self] in
                guard let self else { return }
                guard let cell = collection.cellForItem(at: indexPath) else {
                    return
                }

                Task { [weak self] in
                    guard let self else { return }
                    await dismissAnyPopOver()
                    mostRecentIndexPathActioned = indexPath
                    let a = UIActivityViewController(activityItems: [m.sharingActivitySource], applicationActivities: nil)
                    present(a, animated: true)
                    if let p = a.popoverPresentationController {
                        p.sourceView = cell
                        p.sourceRect = cell.bounds.insetBy(dx: cell.bounds.width * 0.2, dy: cell.bounds.height * 0.2)
                    }
                }
            }, style: [], iconName: "square.and.arrow.up"))
        }

        let confirmTitle = item.shareMode == .sharing ? "Confirm (Will delete from shared users too)" : "Confirm"
        let confirmAction = UIAction(title: confirmTitle) { _ in
            Model.delete(items: [item])
        }
        confirmAction.attributes = .destructive
        let deleteMenu = UIMenu(title: "Delete", image: UIImage(systemName: "bin.xmark"), identifier: nil, options: .destructive, children: [confirmAction])
        let deleteHolder = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: [deleteMenu])
        children.append(deleteHolder)

        return UIMenu(title: "", image: nil, identifier: nil, options: [], children: Array(children))
    }

    func collectionView(_: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        previewForContextMenu(of: configuration)
    }

    func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        if UIAccessibility.isVoiceOverRunning,
           let indexPath = configuration.identifier as? IndexPath,
           let cell = collectionView.cellForItem(at: indexPath) {
            Task {
                try? await Task.sleep(nanoseconds: 1000 * NSEC_PER_MSEC)
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

    private lazy var pasteControl = {
        let config = UIPasteControl.Configuration()
        config.displayMode = .iconOnly
        config.baseBackgroundColor = .tintColor

        #if os(visionOS)
            let controlSize: CGFloat = 44
        #else
            let controlSize: CGFloat = 36
        #endif

        config.cornerStyle = .fixed
        config.cornerRadius = controlSize * 0.5

        let control = UIPasteControl(configuration: config)
        NSLayoutConstraint.activate([
            control.widthAnchor.constraint(equalToConstant: controlSize),
            control.heightAnchor.constraint(equalToConstant: controlSize)
        ])
        control.target = self
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private func updatePasteButton() {
        guard let items = navigationItem.leftBarButtonItems, let indexOfPaste = items.firstIndex(where: { $0.tag == 382_611 }) else {
            return
        }

        items[indexOfPaste].customView = pasteControl
    }

    var currentColumnCount = 1
    private var cellSize = CGSize.zero

    private func createLayout(width: CGFloat, columns: Int, spacing: CGFloat, fixedWidth: CGFloat? = nil, fixedHeight: CGFloat? = nil, dataSource: UICollectionViewDiffableDataSource<SectionIdentifier, ItemIdentifier>) -> UICollectionViewCompositionalLayout {
        currentColumnCount = columns
        let columnCount = CGFloat(columns)
        let extras = spacing * (columnCount + 1)
        let side = ((width - extras) / columnCount).rounded(.down)
        view.window?.windowScene?.session.userInfo?["ItemSide"] = side

        let fixedWidth = fixedWidth ?? side
        let fixedHeight = fixedHeight ?? side
        cellSize = CGSize(width: fixedWidth, height: fixedHeight)
        let itemWidth = NSCollectionLayoutDimension.absolute(fixedWidth)
        let itemHeight = NSCollectionLayoutDimension.absolute(fixedHeight)
        let itemSize = NSCollectionLayoutSize(widthDimension: itemWidth, heightDimension: .fractionalHeight(1))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupsSize = NSCollectionLayoutSize(widthDimension: .absolute(width - spacing - spacing), heightDimension: itemHeight)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupsSize, repeatingSubitem: item, count: columns)
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.supplementaryContentInsetsReference = .none
        section.contentInsetsReference = .none

        let sectionLeft = view.safeAreaInsets.left + spacing
        let sectionRight = view.safeAreaInsets.right + spacing

        let topSpace: CGFloat = if view.traitCollection.horizontalSizeClass == .regular {
            spacing * 0.5
        } else {
            0
        }

        if filter.groupingMode == .flat {
            section.contentInsets = NSDirectionalEdgeInsets(top: topSpace, leading: sectionLeft, bottom: spacing, trailing: sectionRight)
            return UICollectionViewCompositionalLayout(section: section)
        }

        let layout = UICollectionViewCompositionalLayout { index, _ in
            let sectionTitleSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(LabelSectionTitle.height))
            let sectionTitle = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: sectionTitleSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .topLeading)

            switch dataSource.itemIdentifier(for: IndexPath(item: 0, section: index))?.label?.currentDisplayMode {
            case .collapsed, .none:
                section.contentInsets = NSDirectionalEdgeInsets(top: topSpace, leading: sectionLeft, bottom: spacing, trailing: sectionRight)
                section.orthogonalScrollingBehavior = .none
                section.decorationItems = [NSCollectionLayoutDecorationItem.background(elementKind: "SectionBackground")]
                section.boundarySupplementaryItems = [sectionTitle]

            case .scrolling:
                section.contentInsets = NSDirectionalEdgeInsets(top: topSpace, leading: sectionLeft, bottom: spacing, trailing: sectionRight + 50)
                section.orthogonalScrollingBehavior = .continuous
                let fadeSize = NSCollectionLayoutSize(widthDimension: .absolute(50), heightDimension: .absolute(fixedHeight + spacing * 2))
                section.decorationItems = [NSCollectionLayoutDecorationItem.background(elementKind: "SquareBackground")]
                let fader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: fadeSize, elementKind: "ScrollFadeView", containerAnchor: NSCollectionLayoutAnchor(edges: [.trailing, .top, .bottom], absoluteOffset: CGPoint(x: 0, y: -4)))
                fader.extendsBoundary = false
                section.boundarySupplementaryItems = [fader, sectionTitle]

            case .full:
                section.contentInsets = NSDirectionalEdgeInsets(top: topSpace, leading: sectionLeft, bottom: spacing, trailing: sectionRight)
                section.orthogonalScrollingBehavior = .none
                section.decorationItems = [NSCollectionLayoutDecorationItem.background(elementKind: "SquareBackground")]
                section.boundarySupplementaryItems = [sectionTitle]
            }
            return section
        }

        layout.register(SectionBackground.self, forDecorationViewOfKind: "SectionBackground")
        layout.register(SquareBackground.self, forDecorationViewOfKind: "SquareBackground")
        return layout
    }

    private var lastLayoutProcessed: CGFloat = 0

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        setupLayout()
    }

    private func setupLayout() {
        let width = view.safeAreaLayoutGuide.layoutFrame.width
        let wideMode = PersistedOptions.wideMode
        let forceTwoColumn = PersistedOptions.forceTwoColumnPreference

        let key = width + (wideMode ? 1 : 0) + (forceTwoColumn ? 1 : 0)
        if lastLayoutProcessed == key {
            // log("setupLayout not needed")
            return
        }

        lastLayoutProcessed = key

        log("setupLayout ran for: \(key)")

        #if os(visionOS)
            if wideMode {
                if width >= 768 {
                    collection.collectionViewLayout = createLayout(width: width, columns: 2, spacing: 24, fixedHeight: 80, dataSource: dataSource)
                } else {
                    collection.collectionViewLayout = createLayout(width: width, columns: 1, spacing: 24, fixedHeight: 80, dataSource: dataSource)
                }
            } else {
                if width > 1365 {
                    collection.collectionViewLayout = createLayout(width: width, columns: 5, spacing: 24, dataSource: dataSource)
                } else if width > 980 {
                    collection.collectionViewLayout = createLayout(width: width, columns: 4, spacing: 24, dataSource: dataSource)
                } else if width > 438 {
                    collection.collectionViewLayout = createLayout(width: width, columns: 3, spacing: 24, dataSource: dataSource)
                } else if width > 320 {
                    collection.collectionViewLayout = createLayout(width: width, columns: 2, spacing: 24, dataSource: dataSource)
                } else {
                    collection.collectionViewLayout = createLayout(width: width, columns: 1, spacing: 24, dataSource: dataSource)
                }
            }
        #else
            if wideMode {
                if width >= 768 {
                    collection.collectionViewLayout = createLayout(width: width, columns: 2, spacing: 8, fixedHeight: 80, dataSource: dataSource)
                } else {
                    collection.collectionViewLayout = createLayout(width: width, columns: 1, spacing: 8, fixedHeight: 80, dataSource: dataSource)
                }
            } else {
                if width <= 320, !forceTwoColumn {
                    collection.collectionViewLayout = createLayout(width: width, columns: 1, spacing: 10, fixedWidth: 300, fixedHeight: 200, dataSource: dataSource)
                } else if width > 1365 {
                    collection.collectionViewLayout = createLayout(width: width, columns: 5, spacing: 10, dataSource: dataSource)
                } else if width > 980 {
                    collection.collectionViewLayout = createLayout(width: width, columns: 4, spacing: 10, dataSource: dataSource)
                } else if width > 438 {
                    collection.collectionViewLayout = createLayout(width: width, columns: 3, spacing: 8, dataSource: dataSource)
                } else {
                    collection.collectionViewLayout = createLayout(width: width, columns: 2, spacing: 6, dataSource: dataSource)
                }
            }
        #endif

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

    @IBAction private func deleteButtonSelected(_ sender: Any) {
        let candidates = selectedItems
        guard candidates.isPopulated else { return }

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
            if let sender = sender as? UIBarButtonItem {
                p.barButtonItem = sender
            } else if let sender = sender as? UIView {
                p.sourceView = sender
                p.sourceRect = sender.bounds
            } else {
                p.barButtonItem = deleteButton
            }
            p.delegate = self
        }
    }

    private func proceedWithDelete() {
        let candidates = selectedItems
        guard candidates.isPopulated else { return }

        let candidateSet = Set(candidates)
        let itemsToDelete = DropStore.allDrops.filter { candidateSet.contains($0) }
        if itemsToDelete.isPopulated {
            setEditing(false, animated: true)
            Model.delete(items: itemsToDelete)
        }
    }

    private var firstPresentedNavigationController: UINavigationController? {
        let v = navigationController?.presentedViewController ?? presentedViewController?.presentedViewController?.presentedViewController ?? presentedViewController?.presentedViewController ?? presentedViewController
        if let v = v as? UINavigationController {
            return v
        } else if let v = v as? UITabBarController {
            return v.selectedViewController as? UINavigationController
        }
        return nil
    }

    private var currentLabelEditor: LabelEditorController? {
        firstPresentedNavigationController?.viewControllers.first as? LabelEditorController
    }

    private var currentDetailView: DetailController? {
        firstPresentedNavigationController?.viewControllers.first as? DetailController
    }

    private var currentPreviewView: GladysPreviewController? {
        firstPresentedNavigationController?.viewControllers.first as? GladysPreviewController
    }

    private var currentPreferencesView: PreferencesController? {
        firstPresentedNavigationController?.viewControllers.first as? PreferencesController
    }

    private var currentLabelSelector: LabelSelector? {
        firstPresentedNavigationController?.viewControllers.first as? LabelSelector
    }

    private func dismissAnyPopOver() async {
        let firstPresentedAlertController = (navigationController?.presentedViewController ?? presentedViewController) as? UIAlertController
        await firstPresentedAlertController?.dismiss(animated: true)
        await firstPresentedNavigationController?.viewControllers.first?.dismiss(animated: true)
    }

    func dismissAnyPopOverOrModal() async {
        await dismissAnyPopOver()
        if let p = navigationItem.searchController?.presentedViewController ?? navigationController?.presentedViewController {
            await p.dismiss(animated: true)
        }
    }

    //////////////////////////

    func startSearch(_ initialText: String?) async {
        try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
        guard let s = navigationItem.searchController else { return }
        if let initialText {
            s.searchBar.text = initialText
        }
        s.searchBar.becomeFirstResponder()
    }

    func resetSearch(andLabels: Bool) async {
        await dismissAnyPopOverOrModal()

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

    func highlightItem(request: HighlightRequest) async {
        guard let uuid = UUID(uuidString: request.uuid) else { return }
        if filter.filteredDrops.contains(where: { $0.uuid == uuid }) {
            await dismissAnyPopOverOrModal()
        } else if DropStore.indexOfItem(with: request.uuid) != nil {
            await resetSearch(andLabels: true)
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
        }

        if filter.groupingMode == .byLabel, let item = DropStore.item(uuid: request.uuid) {
            let labelList = item.labels
            let labels = Set(labelList)
            let fullLabels = labels.subtracting(filter.labels(for: .full).map(\.function.displayText))
            if fullLabels.isEmpty {
                if let firstLabel = labelList.first {
                    filter.setDisplayMode(to: .full, for: [firstLabel], setAsPreference: false)
                } else if item.isRecentlyAdded {
                    filter.setDisplayMode(to: .full, for: [Filter.Toggle.Function.recentlyAddedItems.displayText], setAsPreference: false)
                } else {
                    filter.setDisplayMode(to: .full, for: [Filter.Toggle.Function.unlabeledItems.displayText], setAsPreference: false)
                }
                updateDataSource(animated: false)
            }
        }

        guard let firstIdentifier = dataSource.snapshot().itemIdentifiers.first(where: { $0.uuid == uuid }),
              let ip = dataSource.indexPath(for: firstIdentifier)
        else { return }

        collection.isUserInteractionEnabled = false

        collection.scrollToItem(at: ip, at: .centeredVertically, animated: false)

        Task {
            try? await Task.sleep(nanoseconds: 500 * NSEC_PER_MSEC)
            if let cell = collection.cellForItem(at: ip) as? ArchivedItemCell {
                cell.flash()
                if let item = cell.archivedDropItem, !item.status.shouldDisplayLoading {
                    switch request.extraAction {
                    case .none:
                        break
                    case .detail:
                        mostRecentIndexPathActioned = ip
                        segue("showDetail", sender: item)
                    case .open:
                        mostRecentIndexPathActioned = ip
                        await item.tryOpen(in: navigationController)
                    case let .preview(childUuid):
                        if let presenter = view.window?.alertPresenter {
                            _ = item.tryPreview(in: presenter, from: cell, preferChild: childUuid)
                        }
                    case .userDefault:
                        self.collectionView(collection, didSelectItemAt: ip)
                    }
                }
            }
            collection.isUserInteractionEnabled = true
        }
    }

    func willDismissSearchController(_: UISearchController) {
        Task {
            await resetSearch(andLabels: false)
        }
    }

    private var searchTimer: PopTimer!

    func updateSearchResults(for _: UISearchController) {
        searchTimer.push()
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

    func forcePaste() async {
        await resetSearch(andLabels: true)
        pasteSelected(pasteButton)
    }

    ///////////////////////////// Accessibility

    private var mostRecentIndexPathActioned: IndexPath?

    private var closestIndexPathSinceLast: IndexPath? {
        let count = filter.filteredDrops.count
        if count == 0 {
            return nil
        }
        guard let mostRecentIndexPathActioned else { return nil }
        if count > mostRecentIndexPathActioned.item {
            return mostRecentIndexPathActioned
        }
        return IndexPath(item: count - 1, section: 0)
    }

    override var initialAccessibilityElement: UIView {
        if let ip = closestIndexPathSinceLast, let cell = collection.cellForItem(at: ip) {
            cell
        } else {
            collection
        }
    }

    @objc private func showLabels() {
        segue("showLabels", sender: nil)
    }

    @IBAction private func showPreferences() {
        Task {
            #if os(visionOS)
                await dismissAnyPopOver()
                let settings = VisionSettingsController()
                settings.modalPresentationStyle = .popover
                present(settings, animated: true)
                if let p = settings.popoverPresentationController {
                    p.sourceItem = settingsButton
                }
            #else
                segue("showPreferences", sender: nil)
            #endif
        }
    }

    @objc private func openSearch() {
        navigationItem.searchController?.searchBar.becomeFirstResponder()
    }

    @objc private func resetLabels() {
        Task {
            await resetSearch(andLabels: true)
        }
    }

    @objc private func toggleEdit() {
        setEditing(!isEditing, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        if collectionView.hasActiveDrop, Singleton.shared.componentDropActiveFromDetailView == nil {
            return false
        }

        if let item = item(for: indexPath) {
            return !item.status.shouldDisplayLoading
        }
        return false
    }

    func collectionView(_: UICollectionView, didBeginMultipleSelectionInteractionAt _: IndexPath) {
        if !isEditing {
            setEditing(true, animated: true)
        }
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
        if focusedItem is ArchivedItemCell {
            a.append(UIKeyCommand(title: "Delete Item", action: #selector(deleteKey), input: UIKeyCommand.inputDelete))
            let ql = UIKeyCommand.makeCommand(input: " ", modifierFlags: [], action: #selector(quickLookFocusedItem), title: "Quick look item")
            a.append(ql)
        }
        return a
    }

    @objc private func deleteKey() {
        guard let focusedCell = focusedItem as? ArchivedItemCell, let item = focusedCell.archivedDropItem else {
            return
        }
        Task {
            let result = await confirm(title: "Delete Selected Item", message: "Are you sure?", action: "Delete", cancel: "Cancel")
            if result {
                Model.delete(items: [item])
            }
        }
    }

    private var searchActive: Bool {
        navigationItem.searchController?.isActive ?? false
    }

    override func updateUserActivityState(_ activity: NSUserActivity) {
        super.updateUserActivityState(activity)
        activity.title = title
        let data = (try? JSONEncoder().encode(filter.labelToggles)) ?? Data()
        let userInfo: [AnyHashable: Any] = [kGladysMainViewSearchText: filter.text ?? "",
                                            kGladysMainViewDisplayMode: filter.groupingMode.rawValue,
                                            kGladysMainViewSections: data]
        activity.addUserInfoEntries(from: userInfo)
    }

    private func addInvites(to item: ArchivedItem, at indexPath: IndexPath) async {
        await dismissAnyPopOver()

        guard let rootRecord = item.cloudKitRecord else { return }

        let provider = NSItemProvider()
        await provider.registerCKShare(container: CloudManager.container, allowedSharingOptions: .standard) {
            let share = try await CloudManager.share(item: item, rootRecord: rootRecord)
            await item.setCloudKitShareRecord(share)
            await item.postModified()
            return share
        }

        let config = UIActivityItemsConfiguration(itemProviders: [provider])
        let activity = UIActivityViewController(activityItemsConfiguration: config)
        activity.view.tintColor = view.tintColor
        present(activity, animated: true)

        if let p = activity.popoverPresentationController, let cell = collection.cellForItem(at: indexPath) {
            p.sourceView = cell
            p.sourceRect = cell.bounds
        }
    }

    private var editingItemId: UUID?

    private func editInvites(in item: ArchivedItem, at indexPath: IndexPath) async {
        await dismissAnyPopOver()

        guard let shareRecord = item.cloudKitShareRecord else { return }
        let cloudSharingController = await UICloudSharingController(share: shareRecord, container: CloudManager.container)

        editingItemId = item.uuid
        cloudSharingController.delegate = self
        cloudSharingController.view.tintColor = view.tintColor
        present(cloudSharingController, animated: true)
        if let p = cloudSharingController.popoverPresentationController, let cell = collection.cellForItem(at: indexPath) {
            p.sourceView = cell
            p.sourceRect = cell.bounds
        }
    }
}

extension ViewController: UICloudSharingControllerDelegate {
    func itemThumbnailData(for _: UICloudSharingController) -> Data? {
        guard let editingItemId, let item = DropStore.item(uuid: editingItemId), let ip = item.imagePath else {
            return nil
        }
        return try? Data(contentsOf: ip)
    }

    func cloudSharingController(_: UICloudSharingController, failedToSaveShareWithError error: Error) {
        Task {
            await genericAlert(title: "Could not share this item", message: error.localizedDescription)
        }
    }

    func itemTitle(for _: UICloudSharingController) -> String? {
        guard let editingItemId, let item = DropStore.item(uuid: editingItemId) else {
            return nil
        }
        return item.trimmedSuggestedName
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        guard let editingItemId, let item = DropStore.item(uuid: editingItemId) else {
            return
        }
        item.cloudKitShareRecord = csc.share
        item.postModified()
    }

    func cloudSharingControllerDidStopSharing(_: UICloudSharingController) {
        guard let editingItemId, let item = DropStore.item(uuid: editingItemId) else {
            return
        }

        Task {
            let wasImported = item.isImportedShare

            do {
                try await CloudManager.deleteShare(item.uuid)
            } catch {
                await genericAlert(title: "Error", message: error.localizedDescription)
                return
            }

            if wasImported {
                try? await Task.sleep(for: .seconds(1))
                Model.delete(items: [item])
            } else {
                item.postModified()
            }
        }
    }
}
