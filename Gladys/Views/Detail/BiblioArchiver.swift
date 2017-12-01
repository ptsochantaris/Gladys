//
//  BiblioArchiver.swift
//  BiblioArchiver
//
//  Created by huangluyang on 16/5/19.
//  Copyright © 2016年 huangluyang. All rights reserved.
//

import Foundation
import Fuzi

/// Archive completion handler block
public typealias ArchiveCompletionHandler = (Data?, [String: String?]?, ArchiveErrorType?) -> ()

/// Fetch resource paths completion handler block
public typealias FetchResourcePathCompletionHandler = (Data?, [String: String?]?, [String]?, ArchiveErrorType?) -> ()

/// Error type
public enum ArchiveErrorType: Error {
    case FetchHTMLError
    case HTMLInvalid
    case FailToInitHTMLDocument
    case FetchResourceFailed
    case PlistSerializeFailed
}

/// Meta data key 'title'
public let ArchivedWebpageMetaKeyTitle = "title"

/// Resource fetch options
public struct ResourceFetchOptions: OptionSet {
    /// rawValue
    public var rawValue: UInt

    /**
     Init options with a raw value

     - parameter rawValue: Options raw value

     - returns: a options
     */
    public init(rawValue: UInt) {
       self.rawValue = rawValue
    }

    /// Fetch image
    public static var FetchImage = ResourceFetchOptions(rawValue: 1 << 1)
    /// Fetch js
    public static var FetchJs = ResourceFetchOptions(rawValue: 1 << 2)
    /// Fetch css
    public static var FetchCss = ResourceFetchOptions(rawValue: 1 << 3)
}

private let kResourceAssembleQueue = "build.bru.gladys.ResourceAssembleQueue"

private let kWebResourceUrl = "WebResourceURL"
private let kWebResourceMIMEType = "WebResourceMIMEType"
private let kWebResourceData = "WebResourceData"
private let kWebResourceTextEncodingName = "WebResourceTextEncodingName"
private let kWebSubresources = "WebSubresources"
private let kWebResourceFrameName = "WebResourceFrameName"
private let kWebMainResource = "WebMainResource"

/// Archiver
public class WebArchiver {
    static private let defaultFetchOptions: ResourceFetchOptions = [.FetchImage, .FetchJs, .FetchCss]

    /**
     Archive web page from url

     - parameter url: The destination url
     - parameter completionHandler: Called when the web page archived
     */
	public static func archiveWebpageFromUrl(url: URL, completionHandler: @escaping ArchiveCompletionHandler) {

        self.resourcePathsFromUrl(url, fetchOptions: defaultFetchOptions) { (data, metaData, resources, error) in
            guard let resources = resources else {
                log("resource fetch error : \(error?.localizedDescription ?? "")")
                completionHandler(nil, nil, .FetchResourceFailed)
                return
            }
            
            let resourceInfo = NSMutableDictionary(capacity: resources.count)

			let assembleQueue = DispatchQueue(label: kResourceAssembleQueue)
			let downloadGroup = DispatchGroup()

            for path in resources {
                guard let resourceUrl = URL(string: path) else {
                    continue
                }
				downloadGroup.enter()
				let task = URLSession.shared.dataTask(with: resourceUrl) { data, response, error in

					guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
						log("url : <\(path)> failed")
						downloadGroup.leave()
						return
					}

					let resource = NSMutableDictionary(capacity: 3)
					resource[kWebResourceUrl] = path
					if let mimeType = response.mimeType {
						resource[kWebResourceMIMEType] = mimeType
					}
					if let data = data {
						resource[kWebResourceData] = data
					}

					assembleQueue.async {
						resourceInfo[path] = resource
					}

					log("url : <\(path)> downloaded")
					downloadGroup.leave()
				}
				task.resume()
			}

			downloadGroup.notify(queue: assembleQueue) {
                let webSubresources = resourceInfo.allValues

                let mainResource = NSMutableDictionary(capacity: 5)
                if let data = data {
                    mainResource[kWebResourceData] = data
                }
                mainResource[kWebResourceFrameName] = ""
                mainResource[kWebResourceMIMEType] = "text/html"
                mainResource[kWebResourceTextEncodingName] = "UTF-8"
                mainResource[kWebResourceUrl] = url.absoluteString

                let webarchive = NSMutableDictionary(capacity: 2)
                webarchive[kWebSubresources] = webSubresources
                webarchive[kWebMainResource] = mainResource

                //log("webarchive : \(webarchive.ba_description())")

                do {
					let webarchiveData = try PropertyListSerialization.data(fromPropertyList: webarchive, format: .binary, options: 0)
                    completionHandler(webarchiveData, metaData, nil)
                } catch {
                    log("plist serialize error : \(error)")
                    completionHandler(nil, metaData, .PlistSerializeFailed)
                }
            }
        }
    }

    /**
     Fetch resource paths within web page from the specific url

     - parameter url:               Destination url
     - parameter fetchOptions:      Fetch options
     - parameter completionHandler: Called when resources fetch finished
     */
	private static func resourcePathsFromUrl(_ url: URL, fetchOptions: ResourceFetchOptions, completionHandler: @escaping FetchResourcePathCompletionHandler) {

        let session = URLSession.shared
		let task = session.dataTask(with: url) { (data, response, error) in

            guard let htmlData = data else {
                log("fetch html error : \(error?.localizedDescription ?? "")")
                completionHandler(data, nil, nil, ArchiveErrorType.FetchHTMLError)
                return
            }

			guard let html = NSString(data: htmlData, encoding: String.Encoding.utf8.rawValue) else {
                log("html invalid")
                completionHandler(data, nil, nil, ArchiveErrorType.HTMLInvalid)
                return
            }

            guard let doc = try? HTMLDocument(string: html as String, encoding: .utf8) else {
                log("init html doc error, html : \(html)")
                completionHandler(data, nil, nil, ArchiveErrorType.FailToInitHTMLDocument)
                return
            }

            log("html --> \(html)")
            
            var metaData = [String: String?]()
            if let htmlTitle = doc.title {
                metaData[ArchivedWebpageMetaKeyTitle] = htmlTitle
            }

            var resources: [String] = []

            let resoucePathFilter: (String?) -> String? = { base in
                guard let base = base else {
                    return nil
                }
                if base.hasPrefix("http") {
                    return base
                } else if base.hasPrefix("//") {
                    return "https:\(base)"
                } else if base.hasPrefix("/"), let host = url.host {
                    return "\(url.scheme ?? "")://\(host)\(base)"
                }
                return nil
            }

            // images
            if fetchOptions.contains(.FetchImage) {
                let imagePaths = doc.xpath("//img[@src]").flatMap({ (node: XMLElement) -> String? in

                    return resoucePathFilter(node["src"])
                })
                resources += imagePaths
            }

            // js
            if fetchOptions.contains(.FetchJs) {
                let jsPaths = doc.xpath("//script[@src]").flatMap({ node in

                    return resoucePathFilter(node["src"])
                })
                resources += jsPaths
            }

            // css
            if fetchOptions.contains(.FetchCss) {
                let cssPaths = doc.xpath("//link[@rel='stylesheet'][@href]").flatMap({ node in

                    return resoucePathFilter(node["href"])
                })
                resources += cssPaths
            }

            completionHandler(data, metaData, resources, nil)
        }
        task.resume()
    }
}

