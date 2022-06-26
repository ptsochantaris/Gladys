import AVFoundation
import Contacts
import MapKit
#if os(iOS)
    import MobileCoreServices
    import UIKit
#else
    import Cocoa
#endif
import GladysFramework

extension Component {
    static let iconPointSize = CGSize(width: 256, height: 256)

    func startIngest(provider: NSItemProvider, encodeAnyUIImage: Bool, createWebArchive: Bool, progress: Progress) async throws {
        progress.totalUnitCount = 2

        do {
            if createWebArchive {
                let data = try await provider.loadDataRepresentation(for: "public.url")
                progress.completedUnitCount += 1
                flags.remove(.isTransferring)

                if flags.contains(.loadingAborted) {
                    throw ingestFailed(error: nil)
                }

                var assignedUrl: URL?
                if let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                    if let urlString = propertyList as? String, let u = URL(string: urlString) { // usually on macOS
                        assignedUrl = u
                    } else if let array = propertyList as? [Any], let urlString = array.first as? String, let u = URL(string: urlString) { // usually on iOS
                        assignedUrl = u
                    }
                }

                guard let url = assignedUrl else {
                    throw ingestFailed(error: nil)
                }

                log(">> Resolved url to read data from: [\(typeIdentifier)]")
                try await ingest(from: url)
                progress.completedUnitCount += 1

            } else {
                let data = try await provider.loadDataRepresentation(for: typeIdentifier)
                progress.completedUnitCount += 1
                flags.remove(.isTransferring)

                if flags.contains(.loadingAborted) {
                    throw ingestFailed(error: nil)
                }

                log(">> Received type: [\(typeIdentifier)]")
                try await ingest(data: data, encodeAnyUIImage: encodeAnyUIImage, storeBytes: true)
                progress.completedUnitCount += 1
            }
        } catch {
            flags.remove(.isTransferring)
            throw ingestFailed(error: error)
        }
    }

    private func ingestFailed(error: Error?) -> Error {
        let error = error ?? GladysError.unknownIngestError.error
        log(">> Error receiving item: \(error.finalDescription)")
        setDisplayIcon(#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
        return error
    }

    func cancelIngest() {
        flags.insert(.loadingAborted)
    }

    private func ingest(from url: URL) async throws {
        // in thread!

        clearCachedFields()
        representedClass = .data
        classWasWrapped = false

        if let scheme = url.scheme, !scheme.hasPrefix("http") {
            try await handleData(emptyData, resolveUrls: false, storeBytes: true)
            return
        }

        let (data, _) = try await WebArchiver.archiveFromUrl(url)
        if flags.contains(.loadingAborted) {
            throw ingestFailed(error: nil)
        }

        try await handleData(data, resolveUrls: false, storeBytes: true)
    }

    private final actor GateKeeper {
        private var counter = 8
        func waitForGate() async {
            while counter < 0 {
                await Task.yield()
            }
            counter -= 1
        }

        func signalGate() {
            counter += 1
        }
    }

    private static let gateKeeper = GateKeeper()

    private func ingest(data: Data, encodeAnyUIImage: Bool = false, storeBytes: Bool) async throws {
        // in thread!
        await Component.gateKeeper.waitForGate()
        defer {
            Task {
                await Component.gateKeeper.signalGate()
            }
        }

        clearCachedFields()

        if data.isPlist, let obj = SafeArchiving.unarchive(data) {
            log("      unwrapped keyed object: \(type(of: obj))")
            classWasWrapped = true

            if let item = obj as? NSString {
                log("      received string: \(item)")
                setTitleInfo(item as String, 10)
                setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
                representedClass = .string
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? NSAttributedString {
                log("      received attributed string: \(item)")
                setTitleInfo(item.string, 7)
                setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
                representedClass = .attributedString
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? COLOR {
                log("      received color: \(item)")
                setTitleInfo("Color \(item.hexValue)", 0)
                setDisplayIcon(#imageLiteral(resourceName: "iconText"), 0, .center)
                representedClass = .color
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? IMAGE {
                log("      received image: \(item)")
                setDisplayIcon(item, 50, .fill)
                if encodeAnyUIImage {
                    log("      will encode it to JPEG, as it's the only image in this parent item")
                    representedClass = .data
                    typeIdentifier = kUTTypeJPEG as String
                    classWasWrapped = false
                    if storeBytes {
                        #if os(iOS)
                            let b = item.jpegData(compressionQuality: 1)
                            setBytes(b)
                        #else
                            let b = (item.representations.first as? NSBitmapImageRep)?.representation(using: .jpeg, properties: [:])
                            setBytes(b ?? emptyData)
                        #endif
                    }
                } else {
                    representedClass = .image
                    if storeBytes {
                        setBytes(data)
                    }
                }
                return

            } else if let item = obj as? MKMapItem {
                log("      received map item: \(item)")
                setDisplayIcon(#imageLiteral(resourceName: "iconMap"), 10, .center)
                representedClass = .mapItem
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? URL {
                try await handleUrl(item, data, storeBytes)
                return

            } else if let item = obj as? NSArray {
                log("      received array: \(item)")
                if item.count == 1 {
                    setTitleInfo("1 Item", 1)
                } else {
                    setTitleInfo("\(item.count) Items", 1)
                }
                setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
                representedClass = .array
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? NSDictionary {
                log("      received dictionary: \(item)")
                if item.count == 1 {
                    setTitleInfo("1 Entry", 1)
                } else {
                    setTitleInfo("\(item.count) Entries", 1)
                }
                setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
                representedClass = .dictionary
                if storeBytes {
                    setBytes(data)
                }
                return
            }
        }

        log("      not a known class, storing data: \(data)")
        representedClass = .data
        try await handleData(data, resolveUrls: true, storeBytes: storeBytes)
    }

    func setTitle(from url: URL) {
        if url.isFileURL {
            setTitleInfo(url.lastPathComponent, 6)
        } else {
            setTitleInfo(url.absoluteString, 6)
        }
    }

    var contentPriority: Int {
        if typeIdentifier == "com.apple.mapkit.map-item" { return 90 }

        if typeConforms(to: kUTTypeVCard) { return 80 }

        if isWebURL { return 70 }

        if typeConforms(to: kUTTypeVideo) { return 60 }

        if typeConforms(to: kUTTypeAudio) { return 50 }

        if typeConforms(to: kUTTypePDF) { return 40 }

        if typeConforms(to: kUTTypeImage) { return 30 }

        if typeConforms(to: kUTTypeText) { return 20 }

        if isFileURL { return 10 }

        return 0
    }

    func replaceURL(_ newUrl: URL) {
        guard isURL else { return }

        let decoded = decode()
        if decoded is URL {
            let data = try? PropertyListSerialization.data(fromPropertyList: newUrl, format: .binary, options: 0)
            setBytes(data)
        } else if let array = decoded as? NSArray {
            let newArray = array.map { (item: Any) -> Any in
                if let text = item as? String, let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty {
                    return newUrl.absoluteString
                } else {
                    return item
                }
            }
            let data = try? PropertyListSerialization.data(fromPropertyList: newArray, format: .binary, options: 0)
            setBytes(data)
        } else {
            let data = Data(newUrl.absoluteString.utf8)
            setBytes(data)
        }
        encodedURLCache = (true, newUrl)
        setTitle(from: newUrl as URL)
        markUpdated()
    }

    func setTitleInfo(_ text: String?, _ priority: Int) {
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

    private func generatePdfPreview() -> IMAGE? {
        guard let document = CGPDFDocument(bytesPath as CFURL), let firstPage = document.page(at: 1) else { return nil }

        let side: CGFloat = 1024

        var pageRect = firstPage.getBoxRect(.cropBox)
        let pdfScale = min(side / pageRect.size.width, side / pageRect.size.height)
        pageRect.origin = .zero
        pageRect.size.width *= pdfScale
        pageRect.size.height *= pdfScale

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
            #if os(iOS)
                return IMAGE(cgImage: cgImage, scale: 1, orientation: .up)
            #else
                return IMAGE(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            #endif
        } else {
            return nil
        }
    }

    func generateMoviePreview() -> IMAGE? {
        var result: IMAGE?
        let fm = FileManager.default
        let tempPath = previewTempPath

        do {
            if fm.fileExists(atPath: tempPath.path) {
                try fm.removeItem(at: tempPath)
            }

            try fm.linkItem(at: bytesPath, to: tempPath)

            let asset = AVURLAsset(url: tempPath, options: nil)
            let imgGenerator = AVAssetImageGenerator(asset: asset)
            imgGenerator.appliesPreferredTrackTransform = true
            let cgImage = try imgGenerator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil)

            #if os(iOS)
                result = UIImage(cgImage: cgImage)
            #else
                result = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            #endif

        } catch {
            log("Error generating movie thumbnail: \(error.finalDescription)")
        }

        if tempPath != bytesPath {
            try? fm.removeItem(at: tempPath)
        }
        return result
    }

    var isText: Bool {
        !typeConforms(to: kUTTypeVCard) && (typeConforms(to: kUTTypeText) || isRichText)
    }

    var isRichText: Bool {
        typeConforms(to: kUTTypeRTF) || typeConforms(to: kUTTypeRTFD) || typeConforms(to: kUTTypeFlatRTFD) || typeIdentifier == "com.apple.uikit.attributedstring"
    }

    var textEncoding: String.Encoding {
        typeConforms(to: kUTTypeUTF16PlainText) ? .utf16 : .utf8
    }

    func handleRemoteUrl(_ url: URL, _: Data, _: Bool) async throws {
        log("      received remote url: \(url.absoluteString)")
        setDisplayIcon(#imageLiteral(resourceName: "iconLink"), 5, .center)
        guard let s = url.scheme, s.hasPrefix("http") else {
            throw GladysError.blankResponse.error
        }

        let res = try? await WebArchiver.fetchWebPreview(for: url)
        if flags.contains(.loadingAborted) {
            throw ingestFailed(error: nil)
        }
        accessoryTitle = res?.title ?? accessoryTitle
        if let image = res?.image {
            if image.size.height > 100 || image.size.width > 200 {
                let thumb = res?.isThumbnail ?? false
                setDisplayIcon(image, 30, thumb ? .fill : .fit)
            } else {
                setDisplayIcon(image, 30, .center)
            }
        }
    }

    func handleData(_ data: Data, resolveUrls: Bool, storeBytes: Bool) async throws {
        if storeBytes {
            setBytes(data)
        }

        if (typeIdentifier == "public.folder" || typeIdentifier == "public.data") && data.isZip {
            typeIdentifier = "public.zip-archive"
        }

        if let image = IMAGE(data: data) {
            setDisplayIcon(image, 50, .fill)

        } else if typeIdentifier == "public.vcard" {
            if let contacts = try? CNContactVCardSerialization.contacts(with: data), let person = contacts.first {
                let name = [person.givenName, person.middleName, person.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                let job = [person.jobTitle, person.organizationName].filter { !$0.isEmpty }.joined(separator: ", ")
                accessoryTitle = [name, job].filter { !$0.isEmpty }.joined(separator: " - ")

                if let imageData = person.imageData, let img = IMAGE(data: imageData) {
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

        } else if typeIdentifier.hasSuffix(".rtf") || typeIdentifier.hasSuffix(".rtfd") || typeIdentifier.hasSuffix(".flat-rtfd") {
            if let data = (decode() as? Data), let s = (try? NSAttributedString(data: data, options: [:], documentAttributes: nil))?.string {
                setTitleInfo(s, 4)
            }
            setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

        } else if resolveUrls, let url = encodedUrl {
            try await handleUrl(url as URL, data, storeBytes)
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
    }

    func reIngest() async throws {
        if let bytesCopy = bytes {
            try await ingest(data: bytesCopy, storeBytes: false)
        }
    }

    func setDisplayIcon(_ icon: IMAGE, _ priority: Int, _ contentMode: ArchivedDropItemDisplayType) {
        Task { @ComponentActor in
            guard priority >= displayIconPriority else {
                return
            }

            let result: IMAGE
            if contentMode == .center || contentMode == .circle {
                result = icon
            } else if contentMode == .fit {
                result = icon.limited(to: Component.iconPointSize, limitTo: 0.75, useScreenScale: true)
            } else {
                result = icon.limited(to: Component.iconPointSize, useScreenScale: true)
            }
            displayIconPriority = priority
            displayIconContentMode = contentMode
            #if os(iOS)
                displayIconTemplate = icon.renderingMode == .alwaysTemplate
            #else
                displayIconTemplate = icon.isTemplate
            #endif
            componentIcon = result
        }
    }
}
