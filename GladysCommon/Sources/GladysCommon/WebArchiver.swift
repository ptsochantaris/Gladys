import Foundation
import SwiftSoup
import UniformTypeIdentifiers

/// Archiver
public final actor WebArchiver {
    public static let shared = WebArchiver()

    /// Error type
    public enum ArchiveErrorType: Error {
        case FetchResourceFailed
        case PlistSerializeFailed
    }

    public func archiveFromUrl(_ urlString: String) async throws -> (Data, String) {
        guard let url = URL(string: urlString) else {
            throw GladysError.networkIssue
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw GladysError.networkIssue
        }
        let mimeType = response.mimeType
        if mimeType == "text/html" {
            return try await archiveWebpageFromUrl(url: urlString, data: data, response: response)
        } else {
            var type: String?
            if let mimeType {
                type = UTType(mimeType: mimeType)?.identifier
            }
            return (data, type ?? "public.data")
        }
    }

    private func archiveWebpageFromUrl(url: String, data: consuming Data, response: HTTPURLResponse) async throws -> (Data, String) {
        guard let pageText = String(data: data, encoding: response.guessedEncoding) else {
            throw GladysError.blankResponse
        }

        let resources = try resourcePaths(from: url, pageText: pageText)

        let resourceInfo = await withTaskGroup { @concurrent group async -> [String: Sendable] in
            for resourceUrlString in resources {
                group.addTask { @concurrent () async -> (String, [String: Sendable])? in
                    guard let resourceUrl = URL(string: resourceUrlString),
                          let (data, response) = try? await URLSession.shared.data(from: resourceUrl),
                          let response = response as? HTTPURLResponse,
                          response.statusCode < 400 else {
                        log("Download failed: \(resourceUrlString)")
                        return nil
                    }

                    var resource: [String: Sendable] = [
                        "WebResourceURL": resourceUrlString
                    ]
                    if let mimeType = response.mimeType {
                        resource["WebResourceMIMEType"] = mimeType
                    }
                    if data.isPopulated {
                        resource["WebResourceData"] = data
                    }
                    log("Downloaded \(resourceUrlString)")
                    return (resourceUrlString, resource)
                }
            }
            let pairs = group.compactMap(\.self)
            var info = [String: Sendable]()
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

    private func resourcePaths(from url: consuming String, pageText: consuming String) throws -> [String] {
        let doc = try SwiftSoup.parse(pageText, url)

        func resoucePathFilter(_ element: SwiftSoup.Element) throws -> String? {
            let base = try element.text(trimAndNormaliseWhitespace: true)
            if base.isPopulated {
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

        let imagePaths = try doc.select("img[src]").compactMap {
            try resoucePathFilter($0)
        }

        let jsPaths = try doc.select("script[src]").compactMap {
            try resoucePathFilter($0)
        }

        let cssPaths = try doc.select("link[rel='stylesheet'][href]").compactMap {
            try resoucePathFilter($0)
        }

        return imagePaths + jsPaths + cssPaths
    }

    /////////////////////////////////////////

    public struct WebPreviewResult: Sendable {
        public let title: String?
        public let image: IMAGE?
        public let isThumbnail: Bool
    }

    public func fetchWebPreview(for urlString: String) async throws -> WebPreviewResult {
        guard let url = URL(string: urlString) else {
            throw GladysError.networkIssue
        }

        var headRequest = URLRequest(url: url)
        log("Investigating possible HTML title from this URL: \(url)")
        headRequest.httpMethod = "head"

        let (_, response) = try await URLSession.shared.data(for: headRequest)
        if let mimeType = response.mimeType, mimeType.hasPrefix("text/html") {
            log("Content for this is HTML, will try to fetch title")
        } else {
            log("Content for this isn't HTML, never mind")
            throw GladysError.blankResponse
        }

        log("Fetching HTML from URL: \(url)")

        let contentRequest = URLRequest(url: url)
        let (data, contentResponse) = try await URLSession.shared.data(for: contentRequest)
        guard let documentText = String(data: data, encoding: contentResponse.guessedEncoding) else {
            throw GladysError.blankResponse
        }

        let htmlDoc = try SwiftSoup.parse(documentText, urlString)

        var title: String?
        if let metaTags = try htmlDoc.head()?.select("meta[property=\"og:title\"]") {
            for node in metaTags {
                let content = try node.attr("content")
                if content.isPopulated {
                    log("Found og title: \(content)")
                    title = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        if (title ?? "").isEmpty {
            log("Falling back to document title")
            let v = try htmlDoc.title().trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isPopulated {
                title = v
            }
        }

        if let title {
            log("Title located at URL: \(title)")
        } else {
            log("No title located at URL")
        }

        func fetchFavIcon() async throws -> WebPreviewResult {
            if let favIconUrl = try repair(path: getFavIconPath(from: htmlDoc), using: url),
               let iconUrl = URL(string: favIconUrl) {
                log("Fetching favicon image for site icon: \(iconUrl)")
                let newImage = try await fetchImage(url: iconUrl)
                return WebPreviewResult(title: title, image: newImage, isThumbnail: false)
            } else {
                return WebPreviewResult(title: title, image: nil, isThumbnail: false)
            }
        }

        let thumbnailUrl = try repair(path: getThumbnailPath(from: htmlDoc, in: url), using: url)
        guard let thumbnailUrl, let iconUrl = URL(string: thumbnailUrl) else {
            return try await fetchFavIcon()
        }

        log("Fetching thumbnail image for site icon: \(iconUrl)")
        if let newImage = try await fetchImage(url: iconUrl) {
            return WebPreviewResult(title: title, image: newImage, isThumbnail: true)
        } else {
            log("Thumbnail fetch failed, falling back to favicon")
            return try await fetchFavIcon()
        }
    }

    private func getThumbnailPath(from htmlDoc: SwiftSoup.Document, in url: URL) throws -> String? {
        if let metaTags = try htmlDoc.head()?.select("meta[property=\"og:image\"]") {
            for node in metaTags {
                let content = try node.attr("content")
                if content.isPopulated {
                    log("Found og image: \(content)")
                    return content
                }
            }
        }

        if let metaTags = try htmlDoc.head()?.select("meta[name=\"thumbnail\" or name=\"image\"]") {
            for node in metaTags {
                let content = try node.attr("content")
                if content.isPopulated {
                    log("Found thumbnail image: \(content)")
                    return content
                }
            }
        }

        if let host = url.host, host.contains("youtube.co") || host.contains("youtu.be") {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            for arg in components?.queryItems ?? [] {
                if arg.name == "v", let youTubeId = arg.value {
                    let thumbnailURL = "https://i.ytimg.com/vi/\(youTubeId)/maxresdefault.jpg"
                    log("Trying YouTube thumbnail image: \(thumbnailURL)")
                    return thumbnailURL
                }
            }
        }

        return nil
    }

    private func getFavIconPath(from htmlDoc: SwiftSoup.Document) throws -> String? {
        var favIconPath = "/favicon.ico"
        if let touchIcons = try htmlDoc.head()?.select("link[rel=\"apple-touch-icon\" or rel=\"apple-touch-icon-precomposed\" or rel=\"icon\" or rel=\"shortcut icon\"]") {
            var imageRank = 0
            for node in touchIcons {
                let isTouch = try node.attr("rel").hasPrefix("apple-touch-icon")
                var rank = isTouch ? 10 : 1
                let sizes = try node.attr("sizes")
                if sizes.isPopulated {
                    let numbers = sizes.split(separator: "x").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if numbers.count > 1 {
                        rank = (Int(numbers[0]) ?? 1) * (Int(numbers[1]) ?? 1) * (isTouch ? 100 : 1)
                    }
                }
                let href = try node.attr("href")
                if href.isPopulated, rank > imageRank {
                    imageRank = rank
                    favIconPath = href
                }
            }
        }
        return favIconPath
    }

    private func repair(path: String?, using url: URL) -> String? {
        guard var path else { return nil }
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
        return iconUrl?.absoluteString
    }

    private func fetchImage(url: URL) async throws -> IMAGE? {
        let (data, _) = try await URLSession.shared.data(from: url)
        log("Image fetched for \(url)")
        return await IMAGE.from(data: data)
    }
}
