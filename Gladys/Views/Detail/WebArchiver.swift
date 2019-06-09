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
		case HTMLInvalid
		case FailToInitHTMLDocument
		case FetchResourceFailed
		case PlistSerializeFailed
	}

	public static func archiveFromUrl(_ url: URL, completionHandler: @escaping ArchiveCompletionHandler) {
		Network.fetch(url) { data, response, error in
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

		let assembleQueue = DispatchQueue.global(qos: .userInitiated)
		let downloadGroup = DispatchGroup()

		for path in resources {
			guard let resourceUrl = URL(string: path) else {
				continue
			}
			downloadGroup.enter()
			Network.fetch(resourceUrl) { data, response, error in

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

				assembleQueue.async {
					resourceInfo[path] = resource
				}

				log("Downloaded \(path)")
				downloadGroup.leave()
			}
		}

		downloadGroup.notify(queue: assembleQueue) {

			let mainResource: [AnyHashable: Any] = [
				"WebResourceFrameName": "",
				"WebResourceMIMEType": response.mimeType ?? "text/html",
				"WebResourceTextEncodingName": response.textEncodingName ?? "UTF-8",
				"WebResourceURL": url.absoluteString,
				"WebResourceData": data
			]

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

		guard let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .ascii) else {
			log("HTML invalid")
			return (nil, .HTMLInvalid)
		}

		guard let doc = try? HTMLDocument(string: html, encoding: .utf8) else {
			log("Init html doc error, html: \(html)")
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
}

