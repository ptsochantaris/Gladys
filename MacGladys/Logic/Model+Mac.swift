import Cocoa

extension Model {

	static var coordinator: NSFileCoordinator {
		return NSFileCoordinator(filePresenter: nil)
	}

	static func prepareToSave() {}

	static func startupComplete() {
		trimTemporaryDirectory()
	}

	private static var eventMonitor: FileMonitor?
	static func startMonitoringForExternalChangesToBlobs() {
		syncWithExternalUpdates()

        eventMonitor = FileMonitor(directory: appStorageUrl) { url in
            let components = url.pathComponents
			let count = components.count

			guard count > 3, components[count-4].hasSuffix(".MacGladys"),
				let potentialParentUUID = UUID(uuidString: String(components[count-3])),
				let potentialComponentUUID = UUID(uuidString: String(components[count-2]))
				else { return }

			log("Examining potential external update for component \(potentialComponentUUID)")
			if let parent = item(uuid: potentialParentUUID), parent.eligibleForExternalUpdateCheck, let component = parent.components.first(where: { $0.uuid == potentialComponentUUID}), component.scanForBlobChanges() {
				parent.needsReIngest = true
				parent.markUpdated()
                log("Detected a modified component blob, uuid \(potentialComponentUUID)")
				parent.reIngest()
            } else {
                log("No change detected")
            }
		}
	}

	private static func syncWithExternalUpdates() {
        let changedDrops = drops.filter { $0.scanForBlobChanges() }
		for item in changedDrops {
			log("Located item whose data has been externally changed: \(item.uuid.uuidString)")
			item.needsReIngest = true
			item.markUpdated()
			item.reIngest()
		}
	}

    static func saveComplete(wasIndexOnly: Bool) {
		if saveIsDueToSyncFetch && !CloudManager.syncDirty {
			saveIsDueToSyncFetch = false
			log("Will not sync to cloud, as the save was due to the completion of a cloud sync")
		} else {
            if CloudManager.syncDirty {
                log("A sync had been requested while syncing, running another sync")
            } else {
                log("Will sync up after a local save")
            }
			CloudManager.sync { error in
				if let error = error {
					log("Error in sync after save: \(error.finalDescription)")
				}
			}
		}
	}
    
    @discardableResult
    static func addItems(from pasteBoard: NSPasteboard, at indexPath: IndexPath, overrides: ImportOverrides?, filterContext: Filter?) -> Bool {
        guard let pasteboardItems = pasteBoard.pasteboardItems else { return false }

        let itemProviders = pasteboardItems.compactMap { pasteboardItem -> NSItemProvider? in
            let extractor = NSItemProvider()
            var count = 0
            
            if let filePromises = pasteBoard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] {
                let destinationUrl = Model.temporaryDirectoryUrl
                for promise in filePromises {
                    for promiseType in promise.fileTypes {
                        let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, promiseType as CFString, nil)?.takeRetainedValue() as String? ?? "public.data"
                        var dropData: Data?
                        let dropLock = DispatchSemaphore(value: 0)
                        promise.receivePromisedFiles(atDestination: destinationUrl, options: [:], operationQueue: OperationQueue()) { url, error in
                            if let error = error {
                                log("Warning, loading error in file drop: \(error.localizedDescription)")
                            }
                            dropData = try? Data(contentsOf: url)
                            dropLock.signal()
                        }
                        
                        count += 1
                        extractor.registerDataRepresentation(forTypeIdentifier: uti, visibility: .all) { callback -> Progress? in
                            let p = Progress()
                            p.totalUnitCount = 1
                            DispatchQueue.global(qos: .background).async {
                                dropLock.wait()
                                p.completedUnitCount += 1
                                callback(dropData, nil)
                            }
                            return p
                        }
                    }
                }
            }
            
            for type in pasteboardItem.types {
                count += 1
                extractor.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { callback -> Progress? in
                    let p = Progress()
                    p.totalUnitCount = 1
                    DispatchQueue.global(qos: .background).async {
                        let data = pasteboardItem.data(forType: type)
                        callback(data, nil)
                        p.completedUnitCount = 1
                    }
                    return p
                }
            }
            return count > 0 ? extractor : nil
        }

        if itemProviders.isEmpty {
            return false
        }

        return addItems(itemProviders: itemProviders, indexPath: indexPath, overrides: overrides, filterContext: filterContext)
    }

    @discardableResult
    static func addItems(itemProviders: [NSItemProvider], indexPath: IndexPath, overrides: ImportOverrides?, filterContext: Filter?) -> Bool {
        var inserted = false
        for provider in itemProviders {
            for newItem in ArchivedItem.importData(providers: [provider], overrides: overrides) {

                var modelIndex = indexPath.item
                if let filterContext = filterContext, filterContext.isFiltering {
                    modelIndex = filterContext.nearestUnfilteredIndexForFilteredIndex(indexPath.item, checkForWeirdness: false)
                    if filterContext.isFilteringLabels && !PersistedOptions.dontAutoLabelNewItems {
                        newItem.labels = filterContext.enabledLabelsForItems
                    }
                }
                Model.drops.insert(newItem, at: modelIndex)
                inserted = true
            }
        }

        if inserted {
            allFilters.forEach {
                $0.updateFilter(signalUpdate: .animated)
            }
        }
        return inserted
    }

    static func importFiles(paths: [String], filterContext: Filter?) {
        let providers = paths.compactMap { path -> NSItemProvider? in
            let url = NSURL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path ?? "", isDirectory: &isDir)
            if isDir.boolValue {
                return NSItemProvider(item: url, typeIdentifier: kUTTypeFileURL as String)
            } else {
                return NSItemProvider(contentsOf: url as URL)
            }
        }
        addItems(itemProviders: providers, indexPath: IndexPath(item: 0, section: 0), overrides: nil, filterContext: filterContext)
    }
    
    static func _updateBadge() {
        let badgeValue: String?
        if CloudManager.showNetwork {
            log("Updating app badge to show network")
            badgeValue = "↔"
        } else if PersistedOptions.badgeIconWithItemCount {
            let count: Int
            if let k = NSApp.keyWindow?.contentViewController as? ViewController {
                count = k.filter.filteredDrops.count
                log("Updating app badge to show current key window item count (\(count))")
            } else if NSApp.orderedWindows.count == 1, let k = NSApp.orderedWindows.first(where: { $0.contentViewController is ViewController })?.gladysController {
                count = k.filter.filteredDrops.count
                log("Updating app badge to show current only window item count (\(count))")
            } else {
                count = Model.drops.count
                log("Updating app badge to show item count (\(count))")
            }
            badgeValue = count > 0 ? String(count) : nil
        } else {
            log("Updating app badge to clear")
            badgeValue = nil
        }
        let tile = NSApp.dockTile
        let v = NSImageView(image: NSApp.applicationIconImage)
        if let badgeValue = badgeValue {
            let label = NSTextField(labelWithString: badgeValue)
            label.alignment = .center
            label.font = NSFont.systemFont(ofSize: 24)
            label.textColor = .white
            label.sizeToFit()
            
            let img = NSImage(named: "statuslabel")!
            let holderFrame = NSRect(origin: .zero, size: NSSize(width: max(label.frame.width + 12, img.size.width), height: img.size.height))

            let holderRect = NSRect(origin: CGPoint(x: v.bounds.width - holderFrame.width + 2.5, y: v.bounds.height - holderFrame.height + 2.5), size: holderFrame.size)
            let holder = NSImageView(frame: holderRect)
            holder.imageScaling = .scaleAxesIndependently
            holder.image = img
            holder.autoresizingMask = [.minYMargin, .minXMargin]
            label.frame = label.frame.offsetBy(dx: (holderFrame.width - label.frame.width) * 0.5, dy: 13)
            holder.addSubview(label)
            v.addSubview(holder)
        }
        tile.contentView = v
        tile.display()
    }
}
