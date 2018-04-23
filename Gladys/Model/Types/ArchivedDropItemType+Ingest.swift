
import UIKit
import Fuzi
import MapKit
import Contacts
import AVFoundation
import MobileCoreServices

extension ArchivedDropItemType {

	private static let ingestQueue = DispatchQueue(label: "build.bru.Gladys.ingestQueue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

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

	func reIngest(delegate: LoadCompletionDelegate) -> Progress {
		self.delegate = delegate
		let overallProgress = Progress(totalUnitCount: 3)
		overallProgress.completedUnitCount = 2
		if loadingError == nil, let bytesCopy = bytes {
			ArchivedDropItemType.ingestQueue.async { [weak self] in
				self?.ingest(data: bytesCopy) {
					overallProgress.completedUnitCount += 1
				}
			}
		} else {
			overallProgress.completedUnitCount += 1
			completeIngest()
		}
		return overallProgress
	}

	private func ingest(data: Data, encodeAnyUIImage: Bool = false, completion: @escaping ()->Void) { // in thread!
		
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
	
	
	private func handleUrl(_ item: URL, _ data: Data) {
		
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

	var isText: Bool {
		return !typeConforms(to: kUTTypeRTF) && (typeConforms(to: kUTTypeText as CFString) || typeIdentifier == "com.apple.uikit.attributedstring")
	}

	var isRichText: Bool {
		return typeConforms(to: kUTTypeRTFD) || typeConforms(to: kUTTypeFlatRTFD) || typeIdentifier == "com.apple.uikit.attributedstring"
	}

	var textEncoding: String.Encoding {
		return typeConforms(to: kUTTypeUTF16PlainText) ? .utf16 : .utf8
	}
	
	private func handleData(_ data: Data) {
		bytes = data
		
		if (typeIdentifier == "public.folder" || typeIdentifier == "public.data") && data.isZip {
			typeIdentifier = "public.zip-archive"
		}
		
		if let image = UIImage(data: data) {
			setDisplayIcon(image, 50, .fill)

		} else if typeIdentifier == "public.vcard" {
			if let contacts = try? CNContactVCardSerialization.contacts(with: data), let person = contacts.first {
				let name = [person.givenName, person.middleName, person.familyName].filter({ !$0.isEmpty }).joined(separator: " ")
				let job = [person.jobTitle, person.organizationName].filter({ !$0.isEmpty }).joined(separator: ", ")
				accessoryTitle = [name, job].filter({ !$0.isEmpty }).joined(separator: " - ")
				
				if let imageData = person.imageData, let img = UIImage(data: imageData) {
					setDisplayIcon(img, 9, .circle)
				} else {
					setDisplayIcon(#imageLiteral(resourceName: "iconPerson"), 5, .center)
				}
			}
			
		} else if typeIdentifier == "public.utf8-plain-text" {
			if let s = String(data: data, encoding: .utf8) {
				setTitleInfo(s, 9)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
			
		} else if typeIdentifier == "public.utf16-plain-text" {
			if let s = String(data: data, encoding: .utf16) {
				setTitleInfo(s, 8)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
			
		} else if typeIdentifier == "public.email-message" {
			setDisplayIcon(#imageLiteral(resourceName: "iconEmail"), 10, .center)
			
		} else if typeIdentifier == "com.apple.mapkit.map-item" {
			setDisplayIcon(#imageLiteral(resourceName: "iconMap"), 5, .center)
			
		} else if typeIdentifier.hasSuffix(".rtf") {
			if let s = (decode() as? NSAttributedString)?.string {
				setTitleInfo(s, 4)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
			
		} else if typeIdentifier.hasSuffix(".rtfd") {
			if let s = (decode() as? NSAttributedString)?.string {
				setTitleInfo(s, 4)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
			
		} else if let url = encodedUrl {
			handleUrl(url as URL, data)
			return // important
			
		} else if typeConforms(to: kUTTypeText as CFString) {
			if let s = String(data: data, encoding: .utf8) {
				setTitleInfo(s, 5)
			}
			setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
			
		} else if typeConforms(to: kUTTypeImage as CFString) {
			setDisplayIcon(#imageLiteral(resourceName: "image"), 5, .center)
			
		} else if typeConforms(to: kUTTypeAudiovisualContent as CFString) {
			if let moviePreview = generateMoviePreview() {
				setDisplayIcon(moviePreview, 50, .fill)
			} else {
				setDisplayIcon(#imageLiteral(resourceName: "movie"), 30, .center)
			}
			
		} else if typeConforms(to: kUTTypeAudio as CFString) {
			setDisplayIcon(#imageLiteral(resourceName: "audio"), 30, .center)
			
		} else if typeConforms(to: kUTTypePDF as CFString), let pdfPreview = generatePdfPreview() {
			if let title = getPdfTitle(), !title.isEmpty {
				setTitleInfo(title, 11)
			}
			setDisplayIcon(pdfPreview, 50, .fill)
			
		} else if typeConforms(to: kUTTypeContent as CFString) {
			setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)

		} else if typeConforms(to: kUTTypeArchive as CFString) {
			setDisplayIcon(#imageLiteral(resourceName: "zip"), 30, .center)

		} else {
			setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
		}

		completeIngest()
	}

	private func getPdfTitle() -> String? {
		if let document = CGPDFDocument(bytesPath as CFURL), let info = document.info {
			var titleStringRef: CGPDFStringRef?
			CGPDFDictionaryGetString(info, "Title", &titleStringRef)
			if let titleStringRef = titleStringRef, let s = CGPDFStringCopyTextString(titleStringRef), !(s as String).isEmpty {
				return s as String
			}
		}
		return nil
	}

	private func generatePdfPreview() -> UIImage? {
		guard let document = CGPDFDocument(bytesPath as CFURL), let firstPage = document.page(at: 1) else { return nil }

		let side: CGFloat = 1024

		var pageRect = firstPage.getBoxRect(.cropBox)
		let pdfScale = min(side / pageRect.size.width, side / pageRect.size.height)
		pageRect.origin = .zero
		pageRect.size.width = pageRect.size.width * pdfScale
		pageRect.size.height = pageRect.size.height * pdfScale

		let c = CGContext(data: nil,
						  width: Int(pageRect.size.width),
						  height: Int(pageRect.size.height),
						  bitsPerComponent: 8,
						  bytesPerRow: Int(pageRect.size.width) * 4,
						  space: CGColorSpaceCreateDeviceRGB(),
						  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)

		guard let context = c else { return nil }

		context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
		context.fill(pageRect)

		context.concatenate(firstPage.getDrawingTransform(.cropBox, rect: pageRect, rotate: 0, preserveAspectRatio: true))
		context.drawPDFPage(firstPage)

		if let cgImage = context.makeImage() {
			return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
		} else {
			return nil
		}
	}

	private func generateMoviePreview() -> UIImage? {
		do {
			let fm = FileManager.default
			let tempPath = previewTempPath
			if fm.fileExists(atPath: tempPath.path) {
				try? fm.removeItem(at: tempPath)
			}
			try? fm.linkItem(at: bytesPath, to: tempPath)

			let asset = AVURLAsset(url: tempPath , options: nil)
			let imgGenerator = AVAssetImageGenerator(asset: asset)
			imgGenerator.appliesPreferredTrackTransform = true
			let cgImage = try imgGenerator.copyCGImage(at: CMTimeMake(0, 1), actualTime: nil)

			if fm.fileExists(atPath: tempPath.path) {
				try? fm.removeItem(at: tempPath)
			}
			return UIImage(cgImage: cgImage)

		} catch let error {
			print("Error generating movie thumbnail: \(error.finalDescription)")
			return nil
		}
	}

	private func setLoadingError(_ message: String) {
		loadingError = NSError(domain: "build.build.Gladys.loadingError", code: 5, userInfo: [NSLocalizedDescriptionKey: message])
		log("Error: \(message)")
	}

	func cancelIngest() {
		loadingAborted = true
		completeIngest()
	}

	private func setDisplayIcon(_ icon: UIImage, _ priority: Int, _ contentMode: ArchivedDropItemDisplayType) {
		guard priority >= displayIconPriority else {
			return
		}

		let result: UIImage
		if contentMode == .center || contentMode == .circle {
			result = icon
		} else if contentMode == .fit {
			result = icon.limited(to: CGSize(width: 256, height: 256), limitTo: 0.75, useScreenScale: true)
		} else {
			result = icon.limited(to: CGSize(width: 256, height: 256), useScreenScale: true)
		}
		displayIconScale = result.scale
		displayIconWidth = result.size.width
		displayIconHeight = result.size.height
		displayIconPriority = priority
		displayIconContentMode = contentMode
		displayIconTemplate = icon.renderingMode == .alwaysTemplate
		displayIcon = result
	}

	private static func webRequest(for url: URL) -> URLRequest {
		let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String

		var request = URLRequest(url: url)
		request.setValue("Gladys/\(v) (iOS; iOS)", forHTTPHeaderField: "User-Agent")
		return request
	}

	private func fetchWebPreview(for url: URL, testing: Bool = true, completion: @escaping (String?, UIImage?)->Void) {

		// in thread!!

		var request = ArchivedDropItemType.webRequest(for: url)
		let U = uuid

		if testing {

			log("\(U): Investigating possible HTML title from this URL: \(url.absoluteString)")

			request.httpMethod = "HEAD"
			let headFetch = URLSession.shared.dataTask(with: request) { data, response, error in
				if let response = response as? HTTPURLResponse {
					if let type = response.mimeType, type.hasPrefix("text/html") {
						log("\(U): Content for this is HTML, will try to fetch title")
						self.fetchWebPreview(for: url, testing: false, completion: completion)
					} else {
						log("\(U): Content for this isn't HTML, never mind")
						completion(nil, nil)
					}
				}
				if let error = error {
					log("\(U): Error while investigating URL: \(error.finalDescription)")
					completion(nil, nil)
				}
			}
			headFetch.resume()

		} else {

			log("\(U): Fetching HTML from URL: \(url.absoluteString)")

			let fetch = URLSession.shared.dataTask(with: request) { data, response, error in
				if let data = data,
					let text = (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)),
					let htmlDoc = try? HTMLDocument(string: text, encoding: .utf8) {

					let title = htmlDoc.title?.trimmingCharacters(in: .whitespacesAndNewlines)
					if let title = title {
						log("\(U): Title located at URL: \(title)")
					} else {
						log("\(U): No title located at URL")
					}

					var largestImagePath = "/favicon.ico"
					var imageRank = 0

					if let touchIcons = htmlDoc.head?.xpath("//link[@rel=\"apple-touch-icon\" or @rel=\"apple-touch-icon-precomposed\" or @rel=\"icon\" or @rel=\"shortcut icon\"]") {
						for node in touchIcons {
							let isTouch = node.attr("rel")?.hasPrefix("apple-touch-icon") ?? false
							var rank = isTouch ? 10 : 1
							if let sizes = node.attr("sizes") {
								let numbers = sizes.split(separator: "x").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
								if numbers.count > 1 {
									rank = (Int(numbers[0]) ?? 1) * (Int(numbers[1]) ?? 1) * (isTouch ? 100 : 1)
								}
							}
							if let href = node.attr("href") {
								if rank > imageRank {
									imageRank = rank
									largestImagePath = href
								}
							}
						}
					}

					var iconUrl: URL?
					if let i = URL(string: largestImagePath), i.scheme != nil {
						iconUrl = i
					} else {
						if var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
							c.path = largestImagePath
							var url = c.url
							if url == nil && (!(largestImagePath.hasPrefix("/") || largestImagePath.hasPrefix("."))) {
								largestImagePath = "/" + largestImagePath
								c.path = largestImagePath
								url = c.url
							}
							iconUrl = url
						}
					}

					if let iconUrl = iconUrl {
						log("\(U): Fetching image for site icon: \(iconUrl)")
						ArchivedDropItemType.fetchImage(url: iconUrl) { newImage in
							completion(title, newImage)
						}
					} else {
						completion(title, nil)
					}

				} else if let error = error {
					log("\(U): Error while fetching title URL: \(error.finalDescription)")
					completion(nil, nil)
				} else {
					log("\(U): Bad HTML data while fetching title URL")
					completion(nil, nil)
				}
			}
			fetch.resume()
		}
	}

	private static func fetchImage(url: URL?, completion: @escaping (UIImage?)->Void) {
		guard let url = url else { completion(nil); return }
		let request = ArchivedDropItemType.webRequest(for: url)
		URLSession.shared.dataTask(with: request) { data, response, error in
			if let data = data {
				log("Image fetched for \(url)")
				completion(UIImage(data: data))
			} else {
				log("Error fetching site icon from \(url)")
				completion(nil)
			}
		}.resume()
	}

	private func completeIngest() {
		let callback = ingestCompletion
		ingestCompletion = nil
		DispatchQueue.main.async {
			self.delegate?.loadCompleted(sender: self)
			self.delegate = nil
			callback?()
		}
	}

	private func copyLocal(_ url: URL) -> URL {

		let newUrl = folderUrl.appendingPathComponent(url.lastPathComponent)
		let f = FileManager.default
		do {
			if f.fileExists(atPath: newUrl.path) {
				try f.removeItem(at: newUrl)
			}
			try f.copyItem(at: url, to: newUrl)
		} catch {
			log("Error while copying item: \(error.finalDescription)")
			loadingError = error
		}
		return newUrl
	}

	private func setTitleInfo(_ text: String?, _ priority: Int) {

		let alignment: NSTextAlignment
		let finalText: String?
		if let text = text, text.count > 200 {
			alignment = .justified
			finalText = text.replacingOccurrences(of: "\n", with: " ")
		} else {
			alignment = .center
			finalText = text
		}
		let final = finalText?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\0", with: "")
		displayTitle = (final?.isEmpty ?? true) ? nil : final
		displayTitlePriority = priority
		displayTitleAlignment = alignment
	}
}
