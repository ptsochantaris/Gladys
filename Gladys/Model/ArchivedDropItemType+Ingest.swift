
import UIKit
import Fuzi
import MapKit
import Contacts

extension ArchivedDropItemType {

	func startIngest(provider: NSItemProvider) {

		provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, error in
			guard let s = self, s.loadingAborted == false else { return }
			if let error = error {
				log(">> Error receiving item: \(error.localizedDescription)")
				s.loadingError = error
				s.setDisplayIcon(#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
				s.signalDone()
			} else if let data = data {
				log(">> Received: [\(provider.suggestedName ?? "")] type: [\(s.typeIdentifier)]")
				s.ingest(data: data, from: provider)
			}
		}
	}

	private func ingest(data: Data, from provider: NSItemProvider) { // in thread!

		let item: NSSecureCoding
		if let obj = (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)) as? NSSecureCoding {
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
			setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)
			setBytes(object: item, originalData: data)
			signalDone()

		} else if let item = item as? NSAttributedString {
			log("      received attributed string: \(item)")
			setTitleInfo(item.string, 7)
			setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)
			setBytes(object: item, originalData: data)
			signalDone()

		} else if let item = item as? UIColor {
			log("      received color: \(item)")
			setBytes(object: item, originalData: data)
			signalDone()

		} else if let item = item as? UIImage {
			log("      received image: \(item)")
			setDisplayIcon(item, 50, .fill)
			setBytes(object: item, originalData: data)
			signalDone()

		} else if let item = item as? MKMapItem {
			log("      received map item: \(item)")
			setDisplayIcon (#imageLiteral(resourceName: "iconMap"), 10, .center)
			setBytes(object: item, originalData: data)
			signalDone()

		} else if let item = item as? URL {
			handleUrl(item, data, provider)

		} else if let item = item as? NSArray {
			log("      received array: \(item)")
			if item.count == 1 {
				setTitleInfo("1 Item", 1)
			} else {
				setTitleInfo("\(item.count) Items", 1)
			}
			setDisplayIcon (#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
			setBytes(object: item, originalData: data)
			signalDone()

		} else if let item = item as? NSDictionary {
			log("      received dictionary: \(item)")
			if item.count == 1 {
				setTitleInfo("1 Entry", 1)
			} else {
				setTitleInfo("\(item.count) Entries", 1)
			}
			setDisplayIcon (#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
			setBytes(object: item, originalData: data)
			signalDone()

		} else {
			log("      received data: \(data)")
			representedClass = "NSData"
			handleData(data, provider)
		}
	}

	private func handleUrl(_ item: URL, _ data: Data?, _ provider: NSItemProvider) {
		setDisplayIcon(#imageLiteral(resourceName: "iconLink"), 5, .center)
		if item.isFileURL {
			signalDone()
			return
		}
		log("      received remote url: \(item.absoluteString)")
		setBytes(object: item as NSURL, originalData: data)
		setTitleInfo(item.absoluteString, 6)
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
				self?.signalDone()
			}
		} else {
			signalDone()
		}
	}

	private func handleData(_ item: Data, _ provider: NSItemProvider) {
		bytes = item

		if let image = UIImage(data: item) {
			setDisplayIcon(image, 40, .fill)
		}

		if typeIdentifier == "public.folder" {
			setDisplayIcon (#imageLiteral(resourceName: "iconFolder"), 5, .center)

		} else if typeIdentifier == "public.vcard" {
			if let contacts = try? CNContactVCardSerialization.contacts(with: item), let person = contacts.first {
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
			let s = String(data: item, encoding: .utf8)
			setTitleInfo(s, 9)
			setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)

		} else if typeIdentifier == "public.utf16-plain-text" {
			let s = String(data: item, encoding: .utf16)
			setTitleInfo(s, 8)
			setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)

		} else if typeIdentifier == "public.email-message" {
			setDisplayIcon (#imageLiteral(resourceName: "iconEmail"), 10, .center)

		} else if typeIdentifier == "com.apple.mapkit.map-item" {
			setDisplayIcon (#imageLiteral(resourceName: "iconMap"), 5, .center)

		} else if typeIdentifier.hasSuffix(".rtf") {
			if let s = (decode() as? NSAttributedString)?.string {
				setTitleInfo(s, 4)
			}
			setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)

		} else if typeIdentifier.hasSuffix(".rtfd") {
			if let s = (decode() as? NSAttributedString)?.string {
				setTitleInfo(s, 4)
			}
			setDisplayIcon (#imageLiteral(resourceName: "iconText"), 5, .center)

		} else if let url = encodedUrl {
			handleUrl(url as URL, item, provider)
			return
		}

		signalDone()
	}

	private func setLoadingError(_ message: String) {
		loadingError = NSError(domain: "build.build.Gladys.loadingError", code: 5, userInfo: [NSLocalizedDescriptionKey: message])
		log("Error: \(message)")
	}

	func cancelIngest() {
		loadingAborted = true
		signalDone()
	}

	private func setDisplayIcon(_ icon: UIImage, _ priority: Int, _ contentMode: ArchivedDropItemDisplayType) {
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
		displayIcon = result
	}

	private func fetchWebPreview(for url: URL, testing: Bool = true, completion: @escaping (String?, UIImage?)->Void) {

		// in thread!!

		var request = URLRequest(url: url)
		request.setValue("Gladys/1.0.0 (iOS; iOS)", forHTTPHeaderField: "User-Agent")

		if testing {

			log("Investigating possible HTML title from this URL: \(url.absoluteString)")

			request.httpMethod = "HEAD"
			let headFetch = URLSession.shared.dataTask(with: request) { data, response, error in
				if let response = response as? HTTPURLResponse {
					if let type = response.mimeType, type.hasPrefix("text/html") {
						log("Content for this is HTML, will try to fetch title")
						self.fetchWebPreview(for: url, testing: false, completion: completion)
					} else {
						log("Content for this isn't HTML, never mind")
						completion(nil, nil)
					}
				}
				if let error = error {
					log("Error while investigating URL: \(error.localizedDescription)")
					completion(nil, nil)
				}
			}
			headFetch.resume()

		} else {

			log("Fetching HTML from URL: \(url.absoluteString)")

			let fetch = URLSession.shared.dataTask(with: request) { data, response, error in
				if let data = data,
					let text = String(data: data, encoding: .utf8),
					let htmlDoc = try? HTMLDocument(string: text, encoding: .utf8) {

					let title = htmlDoc.title?.trimmingCharacters(in: .whitespacesAndNewlines)
					if let title = title {
						log("Title located at URL: \(title)")
					} else {
						log("No title located at URL")
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

					var iconImage: UIImage?
					var iconUrl: URL?
					if let i = URL(string: largestImagePath), i.scheme != nil {
						iconUrl = i
					} else {
						if var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
							c.path = largestImagePath
							iconUrl = c.url
						}
					}

					if let url = iconUrl, let data = try? Data(contentsOf: url, options: []), let image = UIImage(data: data) {
						iconImage = image
					}

					completion(title, iconImage)

				} else if let error = error {
					log("Error while fetching title URL: \(error.localizedDescription)")
					completion(nil, nil)
				} else {
					log("Bad HTML data while fetching title URL")
					completion(nil, nil)
				}
			}
			fetch.resume()
		}
	}

	private func signalDone() {
		DispatchQueue.main.async {
			self.delegate?.loadCompleted(sender: self, success: self.loadingError == nil && !self.loadingAborted)
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
			log("Error while copying item: \(error.localizedDescription)")
			loadingError = error
		}
		return newUrl
	}

	private func setTitleInfo(_ text: String?, _ priority: Int) {

		let alignment: NSTextAlignment
		let finalText: String?
		if let text = text, text.characters.count > 200 {
			alignment = .justified
			finalText = text.replacingOccurrences(of: "\n", with: " ")
		} else {
			alignment = .center
			finalText = text
		}
		let final = finalText?.trimmingCharacters(in: .whitespacesAndNewlines)
		displayTitle = (final?.isEmpty ?? true) ? nil : final
		displayTitlePriority = priority
		displayTitleAlignment = alignment
	}
}
