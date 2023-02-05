import Foundation
import GladysCommon
#if canImport(Cocoa)
    import Cocoa
#endif

@MainActor
enum Model {
    static var brokenMode = false
    static var dataFileLastModified = Date.distantPast

    private static var isStarted = false

    static func reset() {
        DropStore.reset()
        dataFileLastModified = .distantPast
    }

    static func reloadDataIfNeeded(maximumItems: Int? = nil) {
        if brokenMode {
            log("Ignoring load, model is broken, app needs restart.")
            return
        }

        var coordinationError: NSError?
        var loadingError: NSError?
        var didLoad = false

        // withoutChanges because we only signal the provider after we have saved
        coordinator.coordinate(readingItemAt: itemsDirectoryUrl, options: .withoutChanges, error: &coordinationError) { url in

            if !FileManager.default.fileExists(atPath: url.path) {
                DropStore.reset()
                log("Starting fresh store")
                return
            }

            do {
                var shouldLoad = true
                if let dataModified = modificationDate(for: url) {
                    if dataModified == dataFileLastModified {
                        shouldLoad = false
                    } else {
                        dataFileLastModified = dataModified
                    }
                }
                if shouldLoad {
                    log("Needed to reload data, new file date: \(dataFileLastModified)")
                    didLoad = true

                    let start = Date()

                    let d = try Data(contentsOf: url.appendingPathComponent("uuids"))
                    let totalItemsInStore = d.count / 16
                    let itemCount: Int
                    if let maximumItems {
                        itemCount = min(maximumItems, totalItemsInStore)
                    } else {
                        itemCount = totalItemsInStore
                    }

                    let loader = LoaderBuffer(capacity: itemCount)
                    d.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                        let decoder = loadDecoder()
                        let uuidSequence = pointer.bindMemory(to: uuid_t.self).prefix(itemCount)
                        DispatchQueue.concurrentPerform(iterations: itemCount) { count in
                            let us = uuidSequence[count]
                            let u = UUID(uuid: us)
                            let dataPath = url.appendingPathComponent(u.uuidString)
                            if let data = try? Data(contentsOf: dataPath),
                               let item = try? decoder.decode(ArchivedItem.self, from: data) {
                                loader.set(item, at: count)
                            }
                        }
                    }
                    DropStore.initialize(with: loader.result())
                    log("Load time: \(-start.timeIntervalSinceNow) seconds")
                } else {
                    log("No need to reload data")
                }
            } catch {
                log("Loading Error: \(error)")
                loadingError = error as NSError
            }
        }

        if brokenMode {
            log("Model in broken state, further loading or error processing aborted")
            return
        }

        if let loadingError {
            brokenMode = true
            log("Error in loading: \(loadingError)")
            #if MAINAPP || MAC
                let finalError: NSError
                if let underlyingError = loadingError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    finalError = underlyingError
                } else {
                    finalError = loadingError
                }
                Task {
                    await genericAlert(title: "Loading Error (code \(finalError.code))",
                                       message: "This app's data store is not yet accessible. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(loadingError.domain): \(loadingError.localizedDescription)\n\nIf this error persists, please report it to the developer.",
                                       buttonTitle: "Quit")
                    abort()
                }
            #else
                // still boot the item, so it doesn't block others, but keep blank contents and abort after a second or two
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2000 * NSEC_PER_MSEC)
                    exit(0)
                }
            #endif

        } else if let coordinationError {
            brokenMode = true
            log("Error in file coordinator: \(coordinationError)")
            #if MAINAPP || MAC
                let finalError: NSError
                if let underlyingError = coordinationError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    finalError = underlyingError
                } else {
                    finalError = coordinationError
                }
                Task {
                    await genericAlert(title: "Loading Error (code \(finalError.code))",
                                       message: "Could not communicate with an extension. If you keep getting this error, please restart your device, as the system may not have finished updating some components yet.\n\nThe message from the system is:\n\n\(coordinationError.domain): \(coordinationError.localizedDescription)\n\nIf this error persists, please report it to the developer.",
                                       buttonTitle: "Quit")
                    abort()
                }
            #else
                exit(0)
            #endif
        }

        if !brokenMode {
            if isStarted {
                if didLoad {
                    Task { @MainActor in
                        sendNotification(name: .ModelDataUpdated, object: nil)
                    }
                }
            } else {
                isStarted = true
                startupComplete()
            }
        }
    }
}
