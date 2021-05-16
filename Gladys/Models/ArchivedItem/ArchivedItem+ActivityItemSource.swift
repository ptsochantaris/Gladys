//
//  ArchivedItem+ActivityItemSource.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 13/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class ArchivedDropItemActivitySource: NSObject, UIActivityItemSource {
    
    private let component: Component
    private let previewItem: Component.PreviewItem
    
    init(component: Component) {
        self.component = component
        self.previewItem = Component.PreviewItem(typeItem: component)
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return (component.encodedUrl as Any?) ?? (previewItem.previewItemURL as Any?) ?? emptyData
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return component.encodedUrl ?? previewItem.previewItemURL
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return previewItem.previewItemTitle?.truncateWithEllipses(limit: 64) ?? ""
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        return component.componentIcon
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return component.typeIdentifier
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
    var sharingActivitySource: ArchivedDropItemActivitySource {
        return ArchivedDropItemActivitySource(component: self)
    }
}
