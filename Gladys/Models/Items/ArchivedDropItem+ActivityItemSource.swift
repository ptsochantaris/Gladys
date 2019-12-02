//
//  ArchivedDropItem+ActivityItemSource.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 13/11/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import LinkPresentation

final class ArchivedDropItemActivitySource: NSObject, UIActivityItemSource {
    
    private let item: ArchivedDropItem
    
    init(item: ArchivedDropItem) {
        self.item = item
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return item.displayIcon
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return item.mostRelevantTypeItem?.bytes
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return item.trimmedSuggestedName
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        return item.displayIcon
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return item.mostRelevantTypeItem?.typeIdentifier ?? "public.data"
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = item.trimmedSuggestedName
        
        let icon = item.displayIcon
        metadata.imageProvider = NSItemProvider(object: icon)
        metadata.iconProvider = NSItemProvider(object: icon)
        
        let url = item.associatedWebURL
        metadata.originalURL = url
        metadata.url = url
        
        return metadata
    }
}

extension ArchivedDropItem {
    var sharingActivitySource: ArchivedDropItemActivitySource {
        return ArchivedDropItemActivitySource(item: self)
    }
}
