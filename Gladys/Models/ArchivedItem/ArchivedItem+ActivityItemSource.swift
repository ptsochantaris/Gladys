import UIKit

final class ArchivedDropItemActivitySource: NSObject, UIActivityItemSource {
    private let component: Component
    private let previewItem: Component.PreviewItem

    @MainActor
    init(component: Component) {
        self.component = component
        previewItem = Component.PreviewItem(typeItem: component)
        super.init()
    }

    func activityViewControllerPlaceholderItem(_: UIActivityViewController) -> Any {
        (component.encodedUrl as Any?) ?? (previewItem.previewItemURL as Any?) ?? Data()
    }

    func activityViewController(_: UIActivityViewController, itemForActivityType _: UIActivity.ActivityType?) -> Any? {
        component.encodedUrl ?? previewItem.previewItemURL
    }

    func activityViewController(_: UIActivityViewController, subjectForActivityType _: UIActivity.ActivityType?) -> String {
        previewItem.previewItemTitle?.truncateWithEllipses(limit: 64) ?? ""
    }

    func activityViewController(_: UIActivityViewController, thumbnailImageForActivityType _: UIActivity.ActivityType?, suggestedSize _: CGSize) -> UIImage? {
        component.componentIcon
    }

    func activityViewController(_: UIActivityViewController, dataTypeIdentifierForActivityType _: UIActivity.ActivityType?) -> String {
        component.typeIdentifier
    }

    /*
     func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
         let metadata = LPLinkMetadata()
         metadata.title = component.trimmedSuggestedName

         if let icon = component.componentIcon {
             metadata.imageProvider = NSItemProvider(object: icon)
             metadata.iconProvider = NSItemProvider(object: icon)
         }

         if let url = component.encodedUrl as URL? {
             metadata.originalURL = url
             metadata.url = url
         }

         return metadata
     }
      */
}

extension Component {
    @MainActor
    var sharingActivitySource: ArchivedDropItemActivitySource {
        ArchivedDropItemActivitySource(component: self)
    }
}
