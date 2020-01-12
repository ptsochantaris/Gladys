import Cocoa
import ZIPFoundation
import MapKit
import Contacts
import ContactsUI

extension Component {

	var isArchivable: Bool {
		if let e = encodedUrl, !e.isFileURL, e.host != nil, let s = e.scheme, s.hasPrefix("http") {
			return true
		} else {
			return false
		}
	}
    
	var displayIcon: NSImage? {
		set {
            let ipath = imagePath
            if let n = newValue, let data = n.tiffRepresentation {
                try? data.write(to: ipath)
            } else if FileManager.default.fileExists(atPath: ipath.path) {
                try? FileManager.default.removeItem(at: ipath)
            }
		}
		get {
            let i = NSImage(contentsOf: imagePath)
            if let i = i, displayIconTemplate {
                i.isTemplate = true
                let w = i.size.width
                let h = i.size.height
                let scale = min(32.0 / h, 32.0 / w)
                i.size = NSSize(width: w * scale, height: h * scale)
            }
            return i
		}
	}

	private func appendDirectory(_ baseURL: URL, chain: [String], archive: Archive, fm: FileManager) throws {
		let joinedChain = chain.joined(separator: "/")
		let dirURL = baseURL.appendingPathComponent(joinedChain)
		for file in try fm.contentsOfDirectory(atPath: dirURL.path) {
            if flags.contains(.loadingAborted) {
				log("      Interrupted zip operation since ingest was aborted")
				break
			}
			let newURL = dirURL.appendingPathComponent(file)
			var directory: ObjCBool = false
			if fm.fileExists(atPath: newURL.path, isDirectory: &directory) {
				if directory.boolValue {
					var newChain = chain
					newChain.append(file)
					try appendDirectory(baseURL, chain: newChain, archive: archive, fm: fm)
				} else {
					log("      Compressing \(newURL.path)")
					let path = joinedChain + "/" + file
					try archive.addEntry(with: path, relativeTo: baseURL)
				}
			}
		}
	}

    private func handleFileUrl(_ item: URL, _ data: Data, _ storeBytes: Bool, _ andCall: ((Error?)->Void)?) {
        if PersistedOptions.readAndStoreFinderTagsAsLabels {
            let resourceValues = try? item.resourceValues(forKeys: [.tagNamesKey])
            contributedLabels = resourceValues?.tagNames
        } else {
            contributedLabels = nil
        }

		accessoryTitle = item.lastPathComponent
		let fm = FileManager.default
		var directory: ObjCBool = false
		if fm.fileExists(atPath: item.path, isDirectory: &directory) {
			do {
				if directory.boolValue {
					typeIdentifier = kUTTypeZipArchive as String
					setDisplayIcon(#imageLiteral(resourceName: "zip"), 30, .center)
					representedClass = .data
					let tempURL = Model.temporaryDirectoryUrl.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
					let a = Archive(url: tempURL, accessMode: .create)!
					let dirName = item.lastPathComponent
					let item = item.deletingLastPathComponent()
					try appendDirectory(item, chain: [dirName], archive: a, fm: fm)
                    if flags.contains(.loadingAborted) {
						log("      Cancelled zip operation since ingest was aborted")
						return
					}
					try fm.moveAndReplaceItem(at: tempURL, to: bytesPath)
					log("      zipped files at url: \(item.absoluteString)")
                    completeIngest(andCall: andCall)

				} else {
					let ext = item.pathExtension
					if !ext.isEmpty, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue() {
						typeIdentifier = uti as String
					} else {
						typeIdentifier = kUTTypeData as String
					}
					representedClass = .data
					log("      read data from file url: \(item.absoluteString) - type assumed to be \(typeIdentifier)")
					let data = (try? Data(contentsOf: item, options: .mappedIfSafe)) ?? Data()
                    handleData(data, resolveUrls: false, storeBytes: storeBytes, andCall: andCall)
				}

			} catch {
				if storeBytes {
					setBytes(data)
				}
				representedClass = .url
				log("      could not read data from file (\(error.localizedDescription)) treating as local file url: \(item.absoluteString)")
				setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
                completeIngest(andCall: andCall)
			}
		} else {
			if storeBytes {
				setBytes(data)
			}
			representedClass = .url
			log("      received local file url for non-existent file: \(item.absoluteString)")
			setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
			completeIngest(andCall: andCall)
		}
	}

    func handleUrl(_ url: URL, _ data: Data, _ storeBytes: Bool, _ andCall: ((Error?)->Void)?) {

		setTitle(from: url)

		if url.isFileURL {
			handleFileUrl(url, data, storeBytes, andCall)

		} else {
			if storeBytes {
				setBytes(data)
			}
			representedClass = .url
            handleRemoteUrl(url, data, storeBytes, andCall)
		}
	}

	func removeIntents() {}

	func tryOpen(from viewController: NSViewController) {
		let shareItem = objectForShare

		if let shareItem = shareItem as? MKMapItem {
			shareItem.openInMaps(launchOptions: [:])

		} else if let contact = shareItem as? CNContact {
			let c = CNContactViewController(nibName: nil, bundle: nil)
			c.contact = contact
			viewController.presentAsModalWindow(c)

		} else if let item = shareItem as? URL {
			if !NSWorkspace.shared.open(item) {
				let message: String
				if item.isFileURL {
					message = "macOS does not recognise the type of this file"
				} else {
					message = "macOS does not recognise the type of this link"
				}
				genericAlert(title: "Can't Open", message: message)
			}
		} else {
			NSWorkspace.shared.openFile(bytesPath.path)
		}
	}

	func add(to pasteboardItem: NSPasteboardItem) {
		guard hasBytes else { return }

		if let s = encodedUrl?.absoluteString {
            let tid = NSPasteboard.PasteboardType(kUTTypeUTF8PlainText as String)
            pasteboardItem.setString(s, forType: tid)

		} else if classWasWrapped, typeConforms(to: kUTTypePlainText), isPlist, let s = decode() as? String {
			let tid = NSPasteboard.PasteboardType(kUTTypeUTF8PlainText as String)
			pasteboardItem.setString(s, forType: tid)
            
		} else {
			let tid = NSPasteboard.PasteboardType(typeIdentifier)
			pasteboardItem.setData(bytes ?? Data(), forType: tid)
		}
	}

	func pasteboardItem(forDrag: Bool) -> NSPasteboardWriting {
		if forDrag {
            return GladysFilePromiseProvider.provider(for: self, with: oneTitle, extraItems: [self], tags: parent?.labels)
		} else {
			let pi = NSPasteboardItem()
			add(to: pi)
			return pi
		}
	}

	var quickLookItem: PreviewItem {
		return PreviewItem(typeItem: self)
	}

	var canPreview: Bool {
		if let canPreviewCache = canPreviewCache {
			return canPreviewCache
		}
        let res = fileExtension != nil && !(parent?.flags.contains(.needsUnlock) ?? true)
		canPreviewCache = res
		return res
	}

	func scanForBlobChanges() -> Bool {
		var detectedChange = false
		dataAccessQueue.sync {
			let recordLocation = bytesPath
			let fm = FileManager.default
			guard fm.fileExists(atPath: recordLocation.path) else { return }

			if let blobModification = Model.modificationDate(for: recordLocation) {
				if let recordedModification = lastGladysBlobUpdate { // we've already stamped this
					if recordedModification < blobModification { // is the file modified after we stamped it?
						lastGladysBlobUpdate = Date()
						detectedChange = true
					}
				} else {
					lastGladysBlobUpdate = Date() // have modification date but no stamp
				}
			} else {
				let now = Date()
				try? fm.setAttributes([FileAttributeKey.modificationDate: now], ofItemAtPath: recordLocation.path)
				lastGladysBlobUpdate = now // no modification date, no stamp
			}
		}
		return detectedChange
	}

	private static let lastModificationKey = "build.bru.Gladys.lastGladysModification"
	var lastGladysBlobUpdate: Date? { // be sure to protect with dataAccessQueue
		get {
            return FileManager.default.getDateAttribute(Component.lastModificationKey, from: bytesPath)
		}
		set {
            FileManager.default.setDateAttribute(Component.lastModificationKey, at: bytesPath, to: newValue)
		}
	}
    
    var itemProviderForSharing: NSItemProvider {
        let p = NSItemProvider()
        registerForSharing(with: p)
        return p
    }

    func registerForSharing(with provider: NSItemProvider) {
        if let w = objectForShare as? NSItemProviderWriting {
            provider.registerObject(w, visibility: .all)
        } else {
            provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion -> Progress? in
                let p = Progress(totalUnitCount: 1)
                DispatchQueue.global(qos: .userInitiated).async {
                    let response = self.dataForDropping ?? self.bytes
                    p.completedUnitCount = 1
                    completion(response, nil)
                }
                return p
            }
        }
    }
}

