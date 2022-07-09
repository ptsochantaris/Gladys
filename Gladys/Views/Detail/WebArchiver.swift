import Foundation
import Fuzi
import UniformTypeIdentifiers

/// Archiver
final actor WebArchiver {
    static let shared = WebArchiver()

    /// Error type
    enum ArchiveErrorType: Error {
        case FailToInitHTMLDocument
        case FetchResourceFailed
        case PlistSerializeFailed
    }

    func setup() {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
        #if os(iOS)
            URLSession.shared.configuration.httpAdditionalHeaders = ["User-Agent": "Gladys/\(v) (iOS; iOS)"]
        #else
            URLSession.shared.configuration.httpAdditionalHeaders = ["User-Agent": "Gladys/\(v) (macOS; macOS)"]
        #endif
    }

    private func getData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if #available(iOS 15.0, iOSApplicationExtension 15.0, macOS 12.0, *) {
            let res = try await URLSession.shared.data(for: request)
            if let response = res.1 as? HTTPURLResponse {
                return (res.0, response)
            } else {
                throw GladysError.blankResponse.error
            }
        } else {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                    if let data = data, let response = response as? HTTPURLResponse {
                        continuation.resume(with: .success((data, response)))
                    } else {
                        continuation.resume(throwing: error ?? GladysError.blankResponse.error)
                    }
                }
                task.resume()
            }
        }
    }

    private func getData(from url: URL) async throws -> (Data, HTTPURLResponse) {
        return try await getData(for: URLRequest(url: url))
    }

    func archiveFromUrl(_ url: URL) async throws -> (Data, String) {
        let (data, response) = try await getData(from: url)
        if response.mimeType == "text/html" {
            return try await archiveWebpageFromUrl(url: url, data: data, response: response)
        } else {
            var type: String?
            if let mimeType = response.mimeType {
                type = UTType(mimeType: mimeType)?.identifier
            }
            return (data, type ?? "public.data")
        }
    }

    private func archiveWebpageFromUrl(url: URL, data: Data, response: URLResponse) async throws -> (Data, String) {
        let (r, error) = resourcePathsFromUrl(url: url, data: data, response: response)
        guard let resources = r else {
            log("Download error: \(error?.localizedDescription ?? "(No error reported)")")
            throw ArchiveErrorType.FetchResourceFailed
        }

        let resourceInfo = await withTaskGroup(of: (String, [AnyHashable: Any])?.self) { group -> [AnyHashable: Any] in
            for path in resources {
                guard let resourceUrl = URL(string: path) else {
                    continue
                }
                group.addTask { [weak self] in
                    guard let (data, response) = try? await self?.getData(from: resourceUrl), response.statusCode == 200 else {
                        log("Download failed: \(path)")
                        return nil
                    }

                    var resource: [AnyHashable: Any] = [
                        "WebResourceURL": path
                    ]
                    if let mimeType = response.mimeType {
                        resource["WebResourceMIMEType"] = mimeType
                    }
                    if !data.isEmpty {
                        resource["WebResourceData"] = data
                    }
                    log("Downloaded \(path)")
                    return (path, resource)
                }
            }
            let pairs = group.compactMap { $0 }
            var info = [AnyHashable: Any]()
            for await pair in pairs {
                info[pair.0] = pair.1
            }
            return info
        }

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
            return (webarchiveData, "com.apple.webarchive")
        } catch {
            log("Plist serialization error : \(error.localizedDescription)")
            throw ArchiveErrorType.PlistSerializeFailed
        }
    }

    private func resourcePathsFromUrl(url: URL, data htmlData: Data, response _: URLResponse) -> ([String]?, ArchiveErrorType?) {
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

    struct WebPreviewResult {
        let title: String?
        let description: String?
        let image: IMAGE?
        let isThumbnail: Bool
    }

    func fetchWebPreview(for url: URL) async throws -> WebPreviewResult {
        var request = URLRequest(url: url)
        log("Investigating possible HTML title from this URL: \(url.absoluteString)")
        request.httpMethod = "HEAD"

        let (_, response) = try await getData(for: request)
        if let type = response.mimeType, type.hasPrefix("text/html") {
            log("Content for this is HTML, will try to fetch title")
        } else {
            log("Content for this isn't HTML, never mind")
            throw GladysError.blankResponse.error
        }

        log("Fetching HTML from URL: \(url.absoluteString)")
        request.httpMethod = "GET"

        let (data, _) = try await getData(for: request)

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

        if let title = title {
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

        func fetchFavIcon() async throws -> WebPreviewResult {
            let favIconUrl = repair(path: getFavIconPath(from: htmlDoc), using: url)
            if let iconUrl = favIconUrl {
                log("Fetching favicon image for site icon: \(iconUrl)")
                let newImage = try await fetchImage(url: iconUrl)
                return WebPreviewResult(title: title, description: description, image: newImage, isThumbnail: false)
            } else {
                return WebPreviewResult(title: title, description: description, image: nil, isThumbnail: false)
            }
        }

        let thumbnailUrl = repair(path: getThumbnailPath(from: htmlDoc), using: url)
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

    private func repair(path: String?, using url: URL) -> URL? {
        guard var path = path else { return nil }
        var iconUrl: URL?
        if let i = URL(string: path), i.scheme != nil {
            iconUrl = i
        } else {
            if var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
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
        return iconUrl
    }

    ////////////////////////////////////////////

    private func fetchImage(url: URL?) async throws -> IMAGE? {
        guard let url = url else { return nil }
        let req = URLRequest(url: url)
        let (data, _) = try await getData(for: req)
        log("Image fetched for \(url)")
        return IMAGE(data: data)
    }
}
