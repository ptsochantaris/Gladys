import AppIntents
import AppKit
import GladysCommon
import GladysUI
import UniformTypeIdentifiers
import WidgetKit

extension Model {
    static func registerStateHandler() {
        stateHandler = { state in
            switch state {
            case .migrated, .willSave:
                break

            case .startupComplete:
                break

            case let .saveComplete(dueToSyncFetch):
                Task {
                    do {
                        WidgetCenter.shared.reloadAllTimelines()
                        if try await shouldSync(dueToSyncFetch: dueToSyncFetch) {
                            try await CloudManager.syncAfterSaveIfNeeded()
                        }
                    } catch {
                        log("Error in sync after save: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    static func createItem(provider: DataImporter, title: String?, note: String?, labels: [GladysAppIntents.ArchivedItemLabel], currentFilter: Filter?) async throws -> some IntentResult & ReturnsValue<GladysAppIntents.ArchivedItemEntity> & OpensIntent {
        let importOverrides = ImportOverrides(title: title, note: note, labels: labels.map(\.id))
        let result = Model.addItems(itemProviders: [provider], indexPath: IndexPath(item: 0, section: 0), overrides: importOverrides, filterContext: currentFilter)
        return try await GladysAppIntents.processCreationResult(result)
    }

    private static var eventMonitor: FileMonitor?

    static func startMonitoringForExternalChangesToBlobs() {
        syncWithExternalUpdates()

        eventMonitor = FileMonitor(directory: appStorageUrl) { url in
            let components = url.pathComponents
            let count = components.count
            guard count > 3, components[count - 4].hasSuffix(".MacGladys"),
                  let potentialParentUUID = UUID(uuidString: String(components[count - 3])),
                  let potentialComponentUUID = UUID(uuidString: String(components[count - 2]))
            else {
                return
            }

            Task { @MainActor in
                guard let parent = DropStore.item(uuid: potentialParentUUID),
                      parent.eligibleForExternalUpdateCheck,
                      let component = DropStore.component(uuid: potentialParentUUID),
                      component.scanForBlobChanges()
                else { return }

                parent.status = .needsIngest
                parent.markUpdated()
                log("Detected a modified component blob, uuid \(potentialComponentUUID), will re-ingest parent")
                await parent.reIngest()
            }
        }
    }

    private static func syncWithExternalUpdates() {
        let changedDrops = DropStore.allDrops.filter { $0.scanForBlobChanges() }
        for item in changedDrops {
            log("Located item whose data has been externally changed: \(item.uuid.uuidString)")
            item.status = .needsIngest
            item.markUpdated()
            Task {
                await item.reIngest()
            }
        }
    }

    static func importFiles(paths: [String], filterContext: Filter?) {
        let providers = paths.compactMap { path -> DataImporter? in
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let p = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.fileURL.identifier)
                return DataImporter(itemProvider: p)
            } else if let p = NSItemProvider(contentsOf: url) {
                return DataImporter(itemProvider: p)
            } else {
                return nil
            }
        }
        _ = addItems(itemProviders: providers, indexPath: IndexPath(item: 0, section: 0), overrides: nil, filterContext: filterContext)
    }

    nonisolated static func unsafeModificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
