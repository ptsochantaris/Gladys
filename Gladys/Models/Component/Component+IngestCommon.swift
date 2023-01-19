import AVFoundation
import Contacts
import MapKit
#if os(macOS)
    import Cocoa
#else
    import MobileCoreServices
    import UIKit
#endif
import AsyncAlgorithms
import GladysCommon

extension Component {
    static let iconPointSize = CGSize(width: 256, height: 256)

    func startIngest(provider: NSItemProvider, encodeAnyUIImage: Bool, createWebArchive: Bool, progress: Progress) async throws {
        progress.totalUnitCount = 2

        do {
            let data = try await provider.loadDataRepresentation(for: createWebArchive ? "public.url" : typeIdentifier)
            progress.completedUnitCount += 1
            flags.remove(.isTransferring)
            if flags.contains(.loadingAborted) {
                throw GladysError.actionCancelled.error
            }

            if createWebArchive {
                var assignedUrl: URL?
                if let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                    if let urlString = propertyList as? String, let u = URL(string: urlString) { // usually on macOS
                        assignedUrl = u
                    } else if let array = propertyList as? [Any], let urlString = array.first as? String, let u = URL(string: urlString) { // usually on iOS
                        assignedUrl = u
                    }
                }

                guard let assignedUrl else {
                    throw GladysError.actionCancelled.error
                }

                log(">> Resolved url to read data from: [\(typeIdentifier)]")
                try await ingest(from: assignedUrl)

            } else {
                log(">> Received type: [\(typeIdentifier)]")
                try await ingest(data: data, encodeAnyUIImage: encodeAnyUIImage, storeBytes: true)
            }

            progress.completedUnitCount += 1

        } catch {
            flags.remove(.isTransferring)
            try await ingestFailed(error: error)
        }
    }

    private func ingestFailed(error: Error?) async throws {
        let error = error ?? GladysError.unknownIngestError.error
        log(">> Error receiving item: \(error.finalDescription)")
        await setDisplayIcon(#imageLiteral(resourceName: "iconPaperclip"), 0, .center)
        throw error
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
            try await handleData(Data(), resolveUrls: false, storeBytes: true)
            return
        }

        let (data, _) = try await WebArchiver.shared.archiveFromUrl(url.absoluteString)
        if flags.contains(.loadingAborted) {
            try await ingestFailed(error: nil)
        }

        try await handleData(data, resolveUrls: false, storeBytes: true)
    }

    private final class GateKeeper {
        private var channel: AsyncChannel<Int>
        private var iterator: AsyncChannel<Int>.Iterator

        init() {
            let c = AsyncChannel(element: Int.self)
            channel = c
            iterator = c.makeAsyncIterator()
            Task {
                for _ in 0 ..< 12 {
                    await c.send(1)
                }
            }
        }

        func waitForGate() async {
            _ = await iterator.next()!
        }

        func signalGate() async {
            await channel.send(1)
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
                await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
                representedClass = .string
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? NSAttributedString {
                log("      received attributed string: \(item)")
                setTitleInfo(item.string, 7)
                await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)
                representedClass = .attributedString
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? COLOR {
                log("      received color: \(item)")
                setTitleInfo("Color \(item.hexValue)", 0)
                await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 0, .center)
                representedClass = .color
                if storeBytes {
                    setBytes(data)
                }
                return

            } else if let item = obj as? IMAGE {
                log("      received image: \(item)")
                await setDisplayIcon(item, 50, .fill)
                if encodeAnyUIImage {
                    log("      will encode it to JPEG, as it's the only image in this parent item")
                    representedClass = .data
                    typeIdentifier = UTType.jpeg.identifier
                    classWasWrapped = false
                    if storeBytes {
                        #if os(macOS)
                            let b = (item.representations.first as? NSBitmapImageRep)?.representation(using: .jpeg, properties: [:])
                            setBytes(b ?? Data())
                        #else
                            let b = item.jpegData(compressionQuality: 1)
                            setBytes(b)
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
                await setDisplayIcon(#imageLiteral(resourceName: "iconMap"), 10, .center)
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
                await setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
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
                await setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
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

        if typeConforms(to: .vCard) { return 80 }

        if isWebURL { return 70 }

        if typeConforms(to: .video) { return 60 }

        if typeConforms(to: .audio) { return 50 }

        if typeConforms(to: .pdf) { return 40 }

        if typeConforms(to: .image) { return 30 }

        if typeConforms(to: .text) { return 20 }

        if isFileURL { return 10 }

        return 0
    }

    func setTitleInfo(_ text: String?, _ priority: Int) {
        let alignment: NSTextAlignment
        let finalText: String?
        if let text, text.count > 200 {
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
            if let titleStringRef, let s = CGPDFStringCopyTextString(titleStringRef), !(s as String).isEmpty {
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
            #if os(macOS)
                return IMAGE(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            #else
                return IMAGE(cgImage: cgImage, scale: 1, orientation: .up)
            #endif
        } else {
            return nil
        }
    }

    private func generateMoviePreview() -> IMAGE? {
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

            #if os(macOS)
                result = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            #else
                result = UIImage(cgImage: cgImage)
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
        !typeConforms(to: .vCard) && (typeConforms(to: .text) || isRichText)
    }

    var isRichText: Bool {
        typeConforms(to: .rtf) || typeConforms(to: .rtfd) || typeConforms(to: .flatRTFD) || typeIdentifier == "com.apple.uikit.attributedstring"
    }

    var textEncoding: String.Encoding {
        typeConforms(to: .utf16PlainText) ? .utf16 : .utf8
    }

    func handleRemoteUrl(_ url: URL, _: Data, _: Bool) async throws {
        log("      received remote url: \(url.absoluteString)")
        await setDisplayIcon(#imageLiteral(resourceName: "iconLink"), 5, .center)
        guard let s = url.scheme, s.hasPrefix("http") else {
            throw GladysError.blankResponse.error
        }

        let res = try? await WebArchiver.shared.fetchWebPreview(for: url.absoluteString)
        if flags.contains(.loadingAborted) {
            try await ingestFailed(error: nil)
        }
        accessoryTitle = res?.title ?? accessoryTitle
        if let image = res?.image {
            if image.size.height > 100 || image.size.width > 200 {
                let thumb = res?.isThumbnail ?? false
                await setDisplayIcon(image, 30, thumb ? .fill : .fit)
            } else {
                await setDisplayIcon(image, 30, .center)
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

        if let image = await IMAGE.from(data: data) {
            await setDisplayIcon(image, 50, .fill)

        } else if typeIdentifier == "public.vcard" {
            if let contacts = try? CNContactVCardSerialization.contacts(with: data), let person = contacts.first {
                let name = [person.givenName, person.middleName, person.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                let job = [person.jobTitle, person.organizationName].filter { !$0.isEmpty }.joined(separator: ", ")
                accessoryTitle = [name, job].filter { !$0.isEmpty }.joined(separator: " - ")

                if let imageData = person.imageData, let img = await IMAGE.from(data: imageData) {
                    await setDisplayIcon(img, 9, .circle)
                } else {
                    await setDisplayIcon(#imageLiteral(resourceName: "iconPerson"), 5, .center)
                }
            }

        } else if typeIdentifier == "public.utf8-plain-text" {
            if let s = String(data: data, encoding: .utf8) {
                setTitleInfo(s, 9)
            }
            await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

        } else if typeIdentifier == "public.utf16-plain-text" {
            if let s = String(data: data, encoding: .utf16) {
                setTitleInfo(s, 8)
            }
            await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

        } else if typeIdentifier == "public.email-message" {
            await setDisplayIcon(#imageLiteral(resourceName: "iconEmail"), 10, .center)

        } else if typeIdentifier == "com.apple.mapkit.map-item" {
            await setDisplayIcon(#imageLiteral(resourceName: "iconMap"), 5, .center)

        } else if typeIdentifier.hasSuffix(".rtf") || typeIdentifier.hasSuffix(".rtfd") || typeIdentifier.hasSuffix(".flat-rtfd") {
            if let data = (decode() as? Data), let s = (try? NSAttributedString(data: data, options: [:], documentAttributes: nil))?.string {
                setTitleInfo(s, 4)
            }
            await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

        } else if resolveUrls, let url = encodedUrl {
            try await handleUrl(url as URL, data, storeBytes)
            return // important

        } else if typeConforms(to: .text) {
            if let s = String(data: data, encoding: .utf8) {
                setTitleInfo(s, 5)
            }
            await setDisplayIcon(#imageLiteral(resourceName: "iconText"), 5, .center)

        } else if typeConforms(to: .image) {
            await setDisplayIcon(#imageLiteral(resourceName: "image"), 5, .center)

        } else if typeConforms(to: .audiovisualContent) {
            if let moviePreview = generateMoviePreview() {
                await setDisplayIcon(moviePreview, 50, .fill)
            } else {
                await setDisplayIcon(#imageLiteral(resourceName: "movie"), 30, .center)
            }

        } else if typeConforms(to: .audio) {
            await setDisplayIcon(#imageLiteral(resourceName: "audio"), 30, .center)

        } else if typeConforms(to: .pdf), let pdfPreview = generatePdfPreview() {
            if let title = getPdfTitle(), !title.isEmpty {
                setTitleInfo(title, 11)
            }
            await setDisplayIcon(pdfPreview, 50, .fill)

        } else if typeConforms(to: .content) {
            await setDisplayIcon(#imageLiteral(resourceName: "iconBlock"), 5, .center)

        } else if typeConforms(to: .archive) {
            await setDisplayIcon(#imageLiteral(resourceName: "zip"), 30, .center)

        } else {
            await setDisplayIcon(#imageLiteral(resourceName: "iconStickyNote"), 0, .center)
        }
    }

    func reIngest() async throws {
        if let bytes {
            try await ingest(data: bytes, storeBytes: false)
        }
    }

    func setDisplayIcon(_ icon: IMAGE, _ priority: Int, _ contentMode: ArchivedDropItemDisplayType) async {
        guard priority >= displayIconPriority else {
            return
        }

        await Task.detached { [weak self] in
            guard let self else { return }
            let result: IMAGE
            switch contentMode {
            case .fit:
                result = icon.limited(to: Component.iconPointSize, limitTo: 0.75, useScreenScale: true)
            case .fill:
                result = icon.limited(to: Component.iconPointSize, useScreenScale: true)
            case .center, .circle:
                result = icon
            }
            self.componentIcon = result
        }.value

        displayIconPriority = priority
        displayIconContentMode = contentMode
        #if os(macOS)
            displayIconTemplate = icon.isTemplate
        #else
            displayIconTemplate = icon.renderingMode == .alwaysTemplate
        #endif
    }
}
