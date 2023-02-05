import UIKit

struct BackgroundSelectionEvent {
    let scene: UIWindowScene?
    let frame: CGRect?
    let name: String?
}

final class SectionBackground: UICollectionReusableView {}

final class SquareBackground: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .g_expandedSection
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
