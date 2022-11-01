import MapKit
import UIKit

final class KeyboardCell: UICollectionViewCell {
    @IBOutlet private var topLabel: UILabel!
    @IBOutlet private var imageView: UIImageView!

    private var existingPreviewView: UIView?

    override func awakeFromNib() {
        super.awakeFromNib()

        let b = UIView()
        b.backgroundColor = .systemBackground
        b.layer.cornerRadius = 8
        b.clipsToBounds = true
        backgroundView = b

        imageView.layer.cornerRadius = 4
        isAccessibilityElement = true
        accessibilityHint = "Select to send"

        topLabel.font = topLabel.font.withSize(topLabel.font.pointSize - 2)
    }

    var targetedPreviewItem: UITargetedPreview {
        let params = UIDragPreviewParameters()
        params.visiblePath = UIBezierPath(roundedRect: bounds, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 8, height: 8))
        return UITargetedPreview(view: self, parameters: params)
    }

    var dropItem: ArchivedItem? {
        didSet {
            guard let dropItem else { return }
            topLabel.text = dropItem.displayText.0
            imageView.image = dropItem.displayIcon
            switch dropItem.displayMode {
            case .center:
                imageView.contentMode = .center
            case .circle:
                imageView.contentMode = .center
            case .fill:
                imageView.contentMode = .scaleAspectFill
            case .fit:
                imageView.contentMode = .scaleAspectFit
            }
            accessibilityValue = topLabel.text ?? ""

            var wantMapView = false
            var wantColourView = false

            // if we're showing an icon, let's try to enhance things a bit
            if imageView.contentMode == .center, let backgroundItem = dropItem.backgroundInfoObject {
                if let mapItem = backgroundItem as? MKMapItem {
                    wantMapView = true
                    if let m = existingPreviewView as? MiniMapView {
                        m.show(location: mapItem)
                    } else {
                        if let e = existingPreviewView {
                            e.removeFromSuperview()
                        }
                        let m = MiniMapView(at: mapItem)
                        imageView.cover(with: m)
                        existingPreviewView = m
                    }

                } else if let color = backgroundItem as? UIColor {
                    wantColourView = true
                    if let c = existingPreviewView as? ColourView {
                        c.backgroundColor = color
                    } else {
                        if let e = existingPreviewView {
                            e.removeFromSuperview()
                        }
                        let c = ColourView()
                        c.backgroundColor = color
                        imageView.cover(with: c)
                        existingPreviewView = c
                    }
                }
            }

            if !wantMapView, !wantColourView, let e = existingPreviewView {
                e.removeFromSuperview()
                existingPreviewView = nil
            }
        }
    }
}
