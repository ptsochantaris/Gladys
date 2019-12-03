//
//  ArchivedDropItem+ActivityItemSource.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 13/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import LinkPresentation

final class ArchivedDropItemActivitySource: NSObject, UIActivityItemSource {
    
    private let component: ArchivedDropItemType
    private let previewItem: ArchivedDropItemType.PreviewItem
    
    init(component: ArchivedDropItemType) {
        self.component = component
        self.previewItem = ArchivedDropItemType.PreviewItem(typeItem: component)
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return (component.encodedUrl as Any?) ?? (previewItem.previewItemURL as Any?) ?? Data()
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return component.encodedUrl ?? previewItem.previewItemURL
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return previewItem.previewItemTitle?.truncateWithEllipses(limit: 64) ?? ""
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        return component.displayIcon
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return component.typeIdentifier
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = component.trimmedSuggestedName
        
        if let icon = component.displayIcon {
            metadata.imageProvider = NSItemProvider(object: icon)
            metadata.iconProvider = NSItemProvider(object: icon)
        }
        
        if let url = component.encodedUrl as URL? {
            metadata.originalURL = url
            metadata.url = url
        }
        
        return metadata
    }
}

extension ArchivedDropItemType {
    var sharingActivitySource: ArchivedDropItemActivitySource {
        return ArchivedDropItemActivitySource(component: self)
    }
}
