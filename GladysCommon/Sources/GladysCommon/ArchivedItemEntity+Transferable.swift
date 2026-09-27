#if !os(watchOS)
    import CoreTransferable
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// The kinds of content an item can hand over to other apps via Siri and Apple Intelligence.
    /// Worked out when the entity is created, because export conditions have to be decided synchronously.
    nonisolated struct ExportableContent: OptionSet, Sendable {
        let rawValue: Int

        static let image = ExportableContent(rawValue: 1 << 0)
        static let text = ExportableContent(rawValue: 1 << 1)
        static let link = ExportableContent(rawValue: 1 << 2)

        @MainActor
        init(item: ArchivedItem) {
            var content: ExportableContent = []
            for component in item.components {
                if component.typeConforms(to: .image) {
                    content.insert(.image)
                } else if component.isText {
                    content.insert(.text)
                }
            }
            if item.associatedWebURL != nil {
                content.insert(.link)
            }
            self = content
        }

        init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    extension ArchivedItemEntity: Transferable {
        private enum ExportError: Error {
            case contentUnavailable
        }

        public nonisolated static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .png) { entity in
                // Read the raw bytes on the main actor, but convert to PNG off it
                let (data, type) = try await MainActor.run {
                    guard let component = try exportableItem(for: entity).components.first(where: { $0.typeConforms(to: .image) }),
                          let data = component.bytes
                    else {
                        throw ExportError.contentUnavailable
                    }
                    return (data, UTType(component.typeIdentifier))
                }
                guard let png = pngData(from: data, type: type) else {
                    throw ExportError.contentUnavailable
                }
                return png
            }
            .exportingCondition { $0.exportableContent.contains(.image) }

            DataRepresentation(exportedContentType: .utf8PlainText) { entity in
                try await MainActor.run {
                    guard let text = try exportableItem(for: entity).components.lazy.filter(\.isText).compactMap(\.exportableText).first else {
                        throw ExportError.contentUnavailable
                    }
                    return Data(text.utf8)
                }
            }
            .exportingCondition { $0.exportableContent.contains(.text) }

            // The entity already carries the link (and leaves it empty for locked items).
            // A data representation, unlike a proxy, is declared in the App Intents metadata.
            DataRepresentation(exportedContentType: .url) { entity in
                guard let url = entity.url else {
                    throw ExportError.contentUnavailable
                }
                return url.dataRepresentation
            }
            .exportingCondition { $0.exportableContent.contains(.link) }
        }

        /// Loads the item's current state, which may be in memory (main app) or only on disk (widgets, extensions)
        @MainActor
        private static func exportableItem(for entity: ArchivedItemEntity) throws -> ArchivedItem {
            guard let item = DropStore.item(uuid: entity.id) ?? LiteModel.locateItemWithoutLoading(uuid: entity.id.uuidString),
                  !item.isLocked // the item may have been locked since the entity was created
            else {
                throw ExportError.contentUnavailable
            }
            return item
        }

        private nonisolated static func pngData(from data: Data, type: UTType?) -> Data? {
            if type?.conforms(to: .png) == true {
                return data
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                return nil
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(destination, image, nil)
            return CGImageDestinationFinalize(destination) ? output as Data : nil
        }
    }

    private extension Component {
        /// The component's text as a plain string, whether it was stored as a string, attributed string, or raw text data
        var exportableText: String? {
            switch decode() {
            case let string as String:
                string
            case let attributedString as NSAttributedString:
                attributedString.string
            case let data as Data:
                if isRichText {
                    (try? NSAttributedString(data: data, options: [:], documentAttributes: nil))?.string
                } else {
                    String(data: data, encoding: textEncoding)
                }
            default:
                nil
            }
        }
    }
#endif
