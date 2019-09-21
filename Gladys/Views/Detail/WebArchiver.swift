// Heavily modified from BiblioArchiver
// Created by huangluyang on 16/5/19.

#if os(iOS)
import MobileCoreServices
#endif
import Foundation
import Fuzi

/// Archiver
final class WebArchiver {

	/// Archive completion handler block
	typealias ArchiveCompletionHandler = (Data?, String?, ArchiveErrorType?) -> ()

	/// Error type
	enum ArchiveErrorType: Error {
		case FetchHTMLError
		case FailToInitHTMLDocument
		case FetchResourceFailed
		case PlistSerializeFailed
	}

	static func archiveFromUrl(_ url: URL, completionHandler: @escaping ArchiveCompletionHandler) {
		fetch(url) { data, response, error in
			if let data = data, let response = response as? HTTPURLResponse {
				if response.mimeType == "text/html" {
					archiveWebpageFromUrl(url: url, data: data, response: response, completionHandler: completionHandler)
				} else {
					var type: String?
					if let mimeType = response.mimeType {
						type = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType as CFString, nil)?.takeRetainedValue() as String?
					}
					completionHandler(data, type ?? "public.data", nil)
				}
			} else {
				log("Download error: \(error?.localizedDescription ?? "(No error reported)")")
				completionHandler(nil, nil, .FetchHTMLError)
			}
		}
	}

	private static func archiveWebpageFromUrl(url: URL, data: Data, response: HTTPURLResponse, completionHandler: @escaping ArchiveCompletionHandler) {

		let (r, error) = resourcePathsFromUrl(url: url, data: data, response: response)
		guard let resources = r else {
			log("Download error: \(error?.localizedDescription ?? "(No error reported)")")
			completionHandler(nil, nil, .FetchResourceFailed)
			return
		}

		var resourceInfo = [AnyHashable: Any]()
		resourceInfo.reserveCapacity(resources.count)

		let assembleQueue = DispatchQueue(label: "build.bru.Gladys.webArchiveAssembleQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem, target: nil)
		let downloadGroup = DispatchGroup()

		for path in resources {
			guard let resourceUrl = URL(string: path) else {
				continue
			}
			downloadGroup.enter()
			fetch(resourceUrl) { data, response, error in

				guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
					log("Download failed: \(path)")
					downloadGroup.leave()
					return
				}

				var resource: [AnyHashable: Any] = [
					"WebResourceURL": path
				]
				if let mimeType = response.mimeType {
					resource["WebResourceMIMEType"] = mimeType
				}
				if let data = data {
					resource["WebResourceData"] = data
				}

				assembleQueue.sync {
					resourceInfo[path] = resource
				}

				log("Downloaded \(path)")
				downloadGroup.leave()
			}
		}

		downloadGroup.notify(queue: assembleQueue) {

			var mainResource: [AnyHashable: Any] = [
				"WebResourceFrameName": "",
				"WebResourceMIMEType": response.mimeType ?? "text/html",
				"WebResourceURL": url.absoluteString,
				"WebResourceData": data
			]
            
            if let encoding = response.textEncodingName {
                mainResource["WebResourceTextEncodingName"] = encoding
            }

			let webarchive: [AnyHashable: Any] = [
				"WebSubresources": (resourceInfo as NSDictionary).allValues,
				"WebMainResource": mainResource
			]

			do {
				let webarchiveData = try PropertyListSerialization.data(fromPropertyList: webarchive, format: .binary, options: 0)
				completionHandler(webarchiveData, "com.apple.webarchive", nil)
			} catch {
				log("Plist serialization error : \(error)")
				completionHandler(nil, nil, .PlistSerializeFailed)
			}
		}
    }
    
	private static func resourcePathsFromUrl(url: URL, data htmlData: Data, response: HTTPURLResponse) -> ([String]?, ArchiveErrorType?) {
                
        guard let doc = try? HTMLDocument(data: htmlData) else {
			log("Init html doc error")
			return (nil, .FailToInitHTMLDocument)
		}

		var resources: [String] = []

		func resoucePathFilter(_ base: String?) -> String? {
			if let base = base {
				if base.hasPrefix("http") {
					return base
				} else if base.hasPrefix("//") {
					return "https:\(base)"
				} else if base.hasPrefix("/"), let host = url.host {
					return "\(url.scheme ?? "")://\(host)\(base)"
				}
			}
			return nil
		}

		let imagePaths = doc.xpath("//img[@src]").compactMap {
			return resoucePathFilter($0["src"])
		}
		resources += imagePaths

		let jsPaths = doc.xpath("//script[@src]").compactMap {
			return resoucePathFilter($0["src"])
		}
		resources += jsPaths

		let cssPaths = doc.xpath("//link[@rel='stylesheet'][@href]").compactMap {
			return resoucePathFilter($0["href"])
		}
		resources += cssPaths

		return (resources, nil)
    }

	/////////////////////////////////////////

	static func fetchWebPreview(for url: URL, testing: Bool = true, completion: @escaping (String?, String?, IMAGE?, Bool)->Void) {

		// in thread!!

		if testing {

			log("Investigating possible HTML title from this URL: \(url.absoluteString)")

			fetch(url, method: "HEAD") { data, response, error in
				if let response = response as? HTTPURLResponse {
					if let type = response.mimeType, type.hasPrefix("text/html") {
						log("Content for this is HTML, will try to fetch title")
						self.fetchWebPreview(for: url, testing: false, completion: completion)
					} else {
						log("Content for this isn't HTML, never mind")
						completion(nil, nil, nil, false)
					}
				}
				if let error = error {
					log("Error while investigating URL: \(error.finalDescription)")
					completion(nil, nil, nil, false)
				}
			}

		} else {

			log("Fetching HTML from URL: \(url.absoluteString)")

			fetch(url) { data, response, error in
                
				if let data = data, let htmlDoc = try? HTMLDocument(data: data) {
                    
					var title: String?
					if let metaTags = htmlDoc.head?.xpath("//meta[@property=\"og:title\"]") {
						for node in metaTags {
							if let content = node.attr("content") {
								log("Found og title: \(content)")
								title = content.trimmingCharacters(in: .whitespacesAndNewlines)
								break
							}
						}
					}

                    if (title ?? "").isEmpty {
						log("Falling back to libXML title")
						title = htmlDoc.title?.trimmingCharacters(in: .whitespacesAndNewlines)
					}
                    
                    if (title ?? "").isEmpty,
                        let htmlText = NSString(data: data, encoding: htmlDoc.encoding.rawValue),
                        let regex = try? NSRegularExpression(pattern: "\\<title\\>(.+)\\<\\/title\\>", options: .caseInsensitive) {
                        
                        log("Attempting to parse TITLE tag")
                        if let match = regex.firstMatch(in: htmlText as String, options: [], range: NSRange(location: 0, length: htmlText.length)), match.numberOfRanges > 1 {
                            let r1 = match.range(at: 1)
                            let titleString = htmlText.substring(with: r1)
                            title = String(titleString.utf8)
                        }
                    }
                    
                    if let title = title {
						log("Title located at URL: \(title)")
					} else {
						log("No title located at URL")
					}

					let description: String? = nil
					/*if let metaTags = htmlDoc.head?.xpath("//meta[@property=\"og:description\"]") {
					for node in metaTags {
					if let content = node.attr("content") {
					log("Found og summary: \(content)")
					description = content.trimmingCharacters(in: .whitespacesAndNewlines)
					break
					}
					}
					}*/

					func fetchFavIcon() {
						let favIconUrl = self.repair(path: self.getFavIconPath(from: htmlDoc), using: url)
						if let iconUrl = favIconUrl {
							log("Fetching favicon image for site icon: \(iconUrl)")
							fetchImage(url: iconUrl) { newImage in
								completion(title, description, newImage, false)
							}
						} else {
							completion(title, description, nil, false)
						}
					}

					let thumbnailUrl = self.repair(path: self.getThumbnailPath(from: htmlDoc), using: url)
					if let iconUrl = thumbnailUrl {
						log("Fetching thumbnail image for site icon: \(iconUrl)")
						fetchImage(url: iconUrl) { newImage in
							if let newImage = newImage {
								completion(title, description, newImage, true)
							} else {
								log("Thumbnail fetch failed, falling back to favicon")
								fetchFavIcon()
							}
						}
					} else {
						fetchFavIcon()
					}

				} else if let error = error {
					log("Error while fetching title URL: \(error.finalDescription)")
					completion(nil, nil, nil, false)

				} else {
					log("Bad HTML data while fetching title URL")
					completion(nil, nil, nil, false)
				}
			}
		}
	}

	static private func getThumbnailPath(from htmlDoc: HTMLDocument) -> String? {
		var thumbnailPath: String?

		if let metaTags = htmlDoc.head?.xpath("//meta[@property=\"og:image\"]") {
			for node in metaTags {
				if let content = node.attr("content") {
					log("Found og image: \(content)")
					thumbnailPath = content
					break
				}
			}
		}

		if thumbnailPath == nil, let metaTags = htmlDoc.head?.xpath("//meta[@name=\"thumbnail\" or @name=\"image\"]") {
			for node in metaTags {
				if let content = node.attr("content") {
					log("Found thumbnail image: \(content)")
					thumbnailPath = content
					break
				}
			}
		}
		return thumbnailPath
	}

	static private func getFavIconPath(from htmlDoc: HTMLDocument) -> String? {
		var favIconPath = "/favicon.ico"
		if let touchIcons = htmlDoc.head?.xpath("//link[@rel=\"apple-touch-icon\" or @rel=\"apple-touch-icon-precomposed\" or @rel=\"icon\" or @rel=\"shortcut icon\"]") {
			var imageRank = 0
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
						favIconPath = href
					}
				}
			}
		}
		return favIconPath
	}

	static private func repair(path: String?, using url: URL) -> URL? {
		guard var path = path else { return nil }
		var iconUrl: URL?
		if let i = URL(string: path), i.scheme != nil {
			iconUrl = i
		} else {
			if var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
				c.path = path
				var url = c.url
				if url == nil && (!(path.hasPrefix("/") || path.hasPrefix("."))) {
					path = "/" + path
					c.path = path
					url = c.url
				}
				iconUrl = url
			}
		}
		return iconUrl
	}

	////////////////////////////////////////////

	static func fetchImage(url: URL?, completion: @escaping (IMAGE?)->Void) {
		guard let url = url else { completion(nil); return }
		fetch(url) { data, response, error in
			if let data = data {
				log("Image fetched for \(url)")
				completion(IMAGE(data: data))
			} else {
				log("Error fetching site icon from \(url)")
				completion(nil)
			}
		}
	}

	///////////////////////////////////////////////

	static private var taskQueue: OperationQueue = {

		let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
		#if MAC
		URLSession.shared.configuration.httpAdditionalHeaders = ["User-Agent": "Gladys/\(v) (macOS; macOS)"]
		#else
		URLSession.shared.configuration.httpAdditionalHeaders = ["User-Agent": "Gladys/\(v) (iOS; iOS)"]
		#endif

		let o = OperationQueue()
		o.maxConcurrentOperationCount = 8
		return o
	}()

	static private func fetch(_ url: URL, method: String? = nil, result: @escaping (Data?, URLResponse?, Error?) -> Void) {
		var request = URLRequest(url: url)
		if let method = method {
			request.httpMethod = method
		}

		let g = DispatchSemaphore(value: 0)

		let task = URLSession.shared.dataTask(with: url) { data, response, error in
			result(data, response, error)
			g.signal()
		}
		taskQueue.addOperation {
			task.resume()
			g.wait()
		}
	}
}

