
import MapKit
import Contacts
import MobileCoreServices

extension ArchivedDropItemType {

	func startIngest(provider: NSItemProvider, delegate: LoadCompletionDelegate, encodeAnyUIImage: Bool) -> Progress {
		self.delegate = delegate
		let overallProgress = Progress(totalUnitCount: 3)

		let p = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, error in
			guard let s = self, s.loadingAborted == false else { return }
			s.isTransferring = false
			if let data = data {
				ArchivedDropItemType.ingestQueue.async {
					log(">> Received: [\(provider.suggestedName ?? "")] type: [\(s.typeIdentifier)]")
					s.ingest(data: data, encodeAnyUIImage: encodeAnyUIImage) {
						overallProgress.completedUnitCount += 1
					}
				}
			} else {
				let error = error ?? NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown import error"])
				log(">> Error receiving item: \(error.finalDescription)")
				s.loadingError = error
				s.setDisplayIcon(#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
				s.completeIngest()
				overallProgress.completedUnitCount += 1
			}
		}
		overallProgress.addChild(p, withPendingUnitCount: 2)
		return overallProgress
	}

	func ingest(data: Data, encodeAnyUIImage: Bool = false, completion: @escaping ()->Void) { // in thread!
		
		ingestCompletion = completion
		
		let item: NSSecureCoding
		if data.isPlist, let obj = (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)) as? NSSecureCoding {
			log("      unwrapped keyed object: \(type(of:obj))")
			item = obj
			classWasWrapped = true
			
		} else {
			log("      looks like raw data")
			item = data as NSSecureCoding
		}
		
		if let item = item as? NSString {
			log("      received string: \(item)")
			setTitleInfo(item as String, 10)
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
			representedClass = "NSString"
			bytes = data
			completeIngest()
			
		} else if let item = item as? NSAttributedString {
			log("      received attributed string: \(item)")
			setTitleInfo(item.string, 7)
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
			representedClass = "NSAttributedString"
			bytes = data
			completeIngest()
			
		} else if let item = item as? UIColor {
			log("      received color: \(item)")
			representedClass = "UIColor"
			bytes = data
			completeIngest()
			
		} else if let item = item as? UIImage {
			log("      received image: \(item)")
			setDisplayIcon(item, 50, .fill)
			if encodeAnyUIImage {
				log("      will encode it to JPEG, as it's the only image in this parent item")
				representedClass = "NSData"
				typeIdentifier = kUTTypeJPEG as String
				classWasWrapped = false
				DispatchQueue.main.sync {
					bytes = UIImageJPEGRepresentation(item, 1)
				}
			} else {
				representedClass = "UIImage"
				bytes = data
			}
			completeIngest()
			
		} else if let item = item as? MKMapItem {
			log("      received map item: \(item)")
			setDisplayIcon(#imageLiteral(resourceName: "iconMap"), 10, .center)
			representedClass = "MKMapItem"
			bytes = data
			completeIngest()
			
		} else if let item = item as? URL {
			handleUrl(item, data)
			
		} else if let item = item as? NSArray {
			log("      received array: \(item)")
			if item.count == 1 {
				setTitleInfo("1 Item", 1)
			} else {
				setTitleInfo("\(item.count) Items", 1)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
			representedClass = "NSArray"
			bytes = data
			completeIngest()
			
		} else if let item = item as? NSDictionary {
			log("      received dictionary: \(item)")
			if item.count == 1 {
				setTitleInfo("1 Entry", 1)
			} else {
				setTitleInfo("\(item.count) Entries", 1)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
			representedClass = "NSDictionary"
			bytes = data
			completeIngest()
			
		} else {
			log("      received data: \(data)")
			representedClass = "NSData"
			handleData(data)
		}
	}

	func handleUrl(_ item: URL, _ data: Data) {
		
		bytes = data
		representedClass = "URL"
		
		if item.isFileURL {
			setTitleInfo(item.lastPathComponent, 6)
			log("      received local file url: \(item.absoluteString)")
			setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)
			completeIngest()
			return
		} else {
			setTitleInfo(item.absoluteString, 6)
			log("      received remote url: \(item.absoluteString)")
			setDisplayIcon(#imageLiteral(resourceName: "iconLink"), 5, .center)
			if let s = item.scheme, s.hasPrefix("http") {
				fetchWebPreview(for: item) { [weak self] title, image in
					if self?.loadingAborted ?? true { return }
					self?.accessoryTitle = title ?? self?.accessoryTitle
					if let image = image {
						if image.size.height > 100 || image.size.width > 200 {
							self?.setDisplayIcon(image, 30, .fit)
						} else {
							self?.setDisplayIcon(image, 30, .center)
						}
					}
					self?.completeIngest()
				}
			} else {
				completeIngest()
			}
		}
	}
}
