import Foundation
import Fuzi
import UniformTypeIdentifiers
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

extension HTTPClientResponse {
    var mimeType: String? {
        if let ct = headers["Content-Type"].first,
           let mime = ct.split(separator: ";").first {
            return mime.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    var textEncodingName: String? {
        if  let ct = headers["Content-Type"].first,
            let lang = ct.split(separator: ";").last {
            let cs = lang.split(separator: "=")
            if cs.count > 1 {
                return cs[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}

/// Archiver
public final actor WebArchiver {
    public static let shared = WebArchiver()
    
    /// Error type
    public enum ArchiveErrorType: Error {
        case FailToInitHTMLDocument
        case FetchResourceFailed
        case PlistSerializeFailed
    }
            
    private let client = HTTPClient(eventLoopGroupProvider: .createNew,
                                    configuration: {
        var config = HTTPClient.Configuration(certificateVerification: .none,
                                              redirectConfiguration: .follow(max: 4, allowCycles: false),
                                              decompression: .enabled(limit: .none))
        config.httpVersion = .http1Only
        return config
    }())
    
    deinit {
        try? client.syncShutdown()
    }
    
    private let headers = HTTPHeaders([
        ("Accept", "*/*"),
        ("Accept-Language", "en-GB,en;q=0.9"),
        ("User-Agent", "Gladys/1 CFNetwork/1402.0.8 Darwin/22.2.0")
    ])

    private func getData(for request: HTTPClientRequest) async throws -> (Data, HTTPClientResponse) {
        var request = request
        request.headers = headers
        let res = try await client.execute(request, timeout: .seconds(60))
        if request.method == .HEAD {
            return (Data(), res)
        } else {
            let buffer = try await res.body.collect(upTo: Int.max)
            return (Data(buffer: buffer), res)
        }
    }

    private func getData(from url: String) async throws -> (Data, HTTPClientResponse) {
        return try await getData(for: HTTPClientRequest(url: url))
    }

    public func archiveFromUrl(_ url: String) async throws -> (Data, String) {
        let (data, response) = try await getData(from: url)
        let mimeType = response.mimeType
        if mimeType == "text/html" {
            return try await archiveWebpageFromUrl(url: url, data: data, response: response)
        } else {
            var type: String?
            if let mimeType {
                type = UTType(mimeType: mimeType)?.identifier
            }
            return (data, type ?? "public.data")
        }
    }

    private func archiveWebpageFromUrl(url: String, data: Data, response: HTTPClientResponse) async throws -> (Data, String) {
        let (r, error) = resourcePathsFromUrl(url: url, data: data)
        guard let resources = r else {
            log("Download error: \(error?.localizedDescription ?? "(No error reported)")")
            throw ArchiveErrorType.FetchResourceFailed
        }

        let resourceInfo = await withTaskGroup(of: (String, [AnyHashable: Any])?.self) { group -> [AnyHashable: Any] in
            for resourceUrl in resources {
                group.addTask { [weak self] in
                    guard let self, let (data, response) = try? await self.getData(from: resourceUrl), response.status.code == 200 else {
                        log("Download failed: \(resourceUrl)")
                        return nil
                    }

                    var resource: [AnyHashable: Any] = [
                        "WebResourceURL": resourceUrl
                    ]
                    if let mimeType = response.mimeType {
                        resource["WebResourceMIMEType"] = mimeType
                    }
                    if !data.isEmpty {
                        resource["WebResourceData"] = data
                    }
                    log("Downloaded \(resourceUrl)")
                    return (resourceUrl, resource)
                }
            }
            let pairs = group.compactMap { $0 }
            var info = [AnyHashable: Any]()
            for await pair in pairs {
                info[pair.0] = pair.1
            }
            return info
        }

        let mimeType = response.mimeType ?? "text/html"
        var mainResource: [AnyHashable: Any] = [
            "WebResourceFrameName": "",
            "WebResourceMIMEType": mimeType,
            "WebResourceURL": url,
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
            return (webarchiveData, "com.apple.webarchive")
        } catch {
            log("Plist serialization error : \(error.localizedDescription)")
            throw ArchiveErrorType.PlistSerializeFailed
        }
    }

    private func resourcePathsFromUrl(url: String, data htmlData: Data) -> ([String]?, ArchiveErrorType?) {
        guard let doc = try? HTMLDocument(data: htmlData) else {
            log("Init html doc error")
            return (nil, .FailToInitHTMLDocument)
        }

        var resources: [String] = []

        func resoucePathFilter(_ base: String?) -> String? {
            if let base {
                if base.hasPrefix("http") {
                    return base
                } else if base.hasPrefix("//") {
                    return "https:\(base)"
                } else if base.hasPrefix("/"), let url = URL(string: url), let host = url.host {
                    return "\(url.scheme ?? "")://\(host)\(base)"
                }
            }
            return nil
        }

        let imagePaths = doc.xpath("//img[@src]").compactMap {
            resoucePathFilter($0["src"])
        }
        resources += imagePaths

        let jsPaths = doc.xpath("//script[@src]").compactMap {
            resoucePathFilter($0["src"])
        }
        resources += jsPaths

        let cssPaths = doc.xpath("//link[@rel='stylesheet'][@href]").compactMap {
            resoucePathFilter($0["href"])
        }
        resources += cssPaths

        return (resources, nil)
    }

    /////////////////////////////////////////

    public struct WebPreviewResult {
        public let title: String?
        public let description: String?
        public let image: IMAGE?
        public let isThumbnail: Bool
    }

    public func fetchWebPreview(for url: String) async throws -> WebPreviewResult {
        var headRequest = HTTPClientRequest(url: url)
        log("Investigating possible HTML title from this URL: \(url)")
        headRequest.method = .HEAD

        let (_, response) = try await getData(for: headRequest)
        if let mimeType = response.mimeType, mimeType.hasPrefix("text/html") {
            log("Content for this is HTML, will try to fetch title")
        } else {
            log("Content for this isn't HTML, never mind")
            throw GladysError.blankResponse.error
        }

        log("Fetching HTML from URL: \(url)")

        let contentRequest = HTTPClientRequest(url: url)
        let (data, _) = try await getData(for: contentRequest)
        let htmlDoc = try HTMLDocument(data: data)

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

        if let title {
            log("Title located at URL: \(title)")
        } else {
            log("No title located at URL")
        }

        let description: String? = nil
        /* if let metaTags = htmlDoc.head?.xpath("//meta[@property=\"og:description\"]") {
         for node in metaTags {
         if let content = node.attr("content") {
         log("Found og summary: \(content)")
         description = content.trimmingCharacters(in: .whitespacesAndNewlines)
         break
         }
         }
         } */

        let _url = URL(string: url)
        func fetchFavIcon() async throws -> WebPreviewResult {
            let favIconUrl = repair(path: getFavIconPath(from: htmlDoc), using: _url)
            if let iconUrl = favIconUrl {
                log("Fetching favicon image for site icon: \(iconUrl)")
                let newImage = try await fetchImage(url: iconUrl)
                return WebPreviewResult(title: title, description: description, image: newImage, isThumbnail: false)
            } else {
                return WebPreviewResult(title: title, description: description, image: nil, isThumbnail: false)
            }
        }

        let thumbnailUrl = repair(path: getThumbnailPath(from: htmlDoc), using: _url)
        guard let iconUrl = thumbnailUrl else {
            return try await fetchFavIcon()
        }

        log("Fetching thumbnail image for site icon: \(iconUrl)")
        if let newImage = try await fetchImage(url: iconUrl) {
            return WebPreviewResult(title: title, description: description, image: newImage, isThumbnail: true)
        } else {
            log("Thumbnail fetch failed, falling back to favicon")
            return try await fetchFavIcon()
        }
    }

    private func getThumbnailPath(from htmlDoc: HTMLDocument) -> String? {
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

    private func getFavIconPath(from htmlDoc: HTMLDocument) -> String? {
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
                if let href = node.attr("href"), rank > imageRank {
                    imageRank = rank
                    favIconPath = href
                }
            }
        }
        return favIconPath
    }

    private func repair(path: String?, using url: URL?) -> String? {
        guard var path else { return nil }
        var iconUrl: URL?
        if let i = URL(string: path), i.scheme != nil {
            iconUrl = i
        } else {
            if let url, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                c.path = path
                var url = c.url
                if url == nil, !(path.hasPrefix("/") || path.hasPrefix(".")) {
                    path = "/" + path
                    c.path = path
                    url = c.url
                }
                iconUrl = url
            }
        }
        return iconUrl?.absoluteString
    }

    ////////////////////////////////////////////

    private func fetchImage(url: String?) async throws -> IMAGE? {
        guard let url else { return nil }
        let (data, _) = try await getData(from: url)
        log("Image fetched for \(url)")
        return await IMAGE.from(data: data)
    }
}
