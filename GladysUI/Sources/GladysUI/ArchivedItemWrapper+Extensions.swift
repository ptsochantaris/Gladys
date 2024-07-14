import Foundation
import GladysCommon
import SwiftUI

extension ArchivedItemWrapper {
    @ViewBuilder
    func createLabelView(width: CGFloat, alignment: NSTextAlignment) -> (some View)? {
        if PersistedOptions.displayLabelsInMainView, labels.isPopulated {
            TagCloudView(wrapper: self, cellWidth: width, alignment: alignment)
                .frame(maxWidth: width, minHeight: 0, alignment: .top)
                .fixedSize()
                .clipped()
                .zIndex(2)
        }
    }

    func createShareInfo() -> (imageName: String, labelText: String)? {
        switch shareMode {
        case .elsewhereReadOnly, .elsewhereReadWrite:
            if let name = shareOwnerDescription {
                (imageName: "person.crop.circle.badge.checkmark", "Shared by \(name)")
            } else {
                (imageName: "person.crop.circle.badge.checkmark", "Participated")
            }
        case .sharing:
            (imageName: isShareWithOnlyOwner ? "person.crop.circle.badge.clock.fill" : "person.crop.circle.fill.badge.checkmark", labelText: "Shared")
        case .none:
            nil
        }
    }
}
