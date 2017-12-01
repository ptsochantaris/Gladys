// Heavily modified from BiblioArchiver
// Created by huangluyang on 16/5/19.

import Foundation
import Fuzi

/// Archive completion handler block
public typealias ArchiveCompletionHandler = (Data?, ArchiveErrorType?) -> ()

/// Fetch resource paths completion handler block
public typealias FetchResourcePathCompletionHandler = (Data?, HTTPURLResponse?, [String]?, ArchiveErrorType?) -> ()

/// Error type
public enum ArchiveErrorType: Error {
    case FetchHTMLError
    case HTMLInvalid
    case FailToInitHTMLDocument
    case FetchResourceFailed
    case PlistSerializeFailed
}

/// Archiver
public class WebArchiver {
	public static func archiveWebpageFromUrl(url: URL, completionHandler: @escaping ArchiveCompletionHandler) {

        resourcePathsFromUrl(url) { data, response, resources, error in
            guard let resources = resources else {
                log("Download error: \(error?.localizedDescription ?? "(No error reported)")")
                completionHandler(nil, .FetchResourceFailed)
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
				let task = URLSession.shared.dataTask(with: resourceUrl) { data, response, error in

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
				task.resume()
			}

			downloadGroup.notify(queue: assembleQueue) {

				var mainResource: [AnyHashable: Any] = [
					"WebResourceFrameName": "",
					"WebResourceMIMEType": response?.mimeType ?? "text/html",
					"WebResourceTextEncodingName": response?.textEncodingName ?? "UTF-8",
					"WebResourceURL": url.absoluteString
				]

				if let data = data {
					mainResource["WebResourceData"] = data
				}

                let webarchive: [AnyHashable: Any] = [
					"WebSubresources": (resourceInfo as NSDictionary).allValues,
					"WebMainResource": mainResource
				]

                do {
					let webarchiveData = try PropertyListSerialization.data(fromPropertyList: webarchive, format: .binary, options: 0)
                    completionHandler(webarchiveData, nil)
                } catch {
                    log("Plist serialization error : \(error)")
                    completionHandler(nil, .PlistSerializeFailed)
                }
            }
        }
    }

	private static func resourcePathsFromUrl(_ url: URL, completionHandler: @escaping FetchResourcePathCompletionHandler) {

		let task = URLSession.shared.dataTask(with: url) { data, response, error in

			let response = response as? HTTPURLResponse

            guard let htmlData = data else {
                log("Fetch html error: \(error?.localizedDescription ?? "")")
                completionHandler(data, response, nil, ArchiveErrorType.FetchHTMLError)
                return
            }

			guard let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .ascii) else {
                log("HTML invalid")
                completionHandler(data, response, nil, ArchiveErrorType.HTMLInvalid)
                return
            }

            guard let doc = try? HTMLDocument(string: html, encoding: .utf8) else {
                log("Init html doc error, html: \(html)")
                completionHandler(data, response, nil, ArchiveErrorType.FailToInitHTMLDocument)
                return
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

			let imagePaths = doc.xpath("//img[@src]").flatMap {
				return resoucePathFilter($0["src"])
			}
			resources += imagePaths

			let jsPaths = doc.xpath("//script[@src]").flatMap {
				return resoucePathFilter($0["src"])
			}
			resources += jsPaths

			let cssPaths = doc.xpath("//link[@rel='stylesheet'][@href]").flatMap {
				return resoucePathFilter($0["href"])
			}
			resources += cssPaths

            completionHandler(data, response, resources, nil)
        }
        task.resume()
    }
}

