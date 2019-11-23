//
//  TodayCell.swift
//  GladysToday
//
//  Created by Paul Tsochantaris on 06/11/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import MapKit

private let todayCellFormatter: DateFormatter = {
	let d = DateFormatter()
	d.doesRelativeDateFormatting = true
	d.dateStyle = .short
	d.timeStyle = .short
	return d
}()

extension Notification.Name {
	static let OpenParentApp = Notification.Name("OpenParentApp")
}

final class TodayCell: UICollectionViewCell {

	@IBOutlet private weak var topLabel: UILabel!
	@IBOutlet private weak var bottomLabel: UILabel!
	@IBOutlet private weak var imageView: UIImageView!

	private var existingPreviewView: UIView?

	override func awakeFromNib() {
		super.awakeFromNib()

		let backgroundEffect = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
		backgroundEffect.layer.cornerRadius = 10
		backgroundEffect.clipsToBounds = true
		backgroundView = backgroundEffect

        let imageEffect = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
		imageEffect.layer.cornerRadius = 5
		imageEffect.clipsToBounds = true
		imageView.coverUnder(with: imageEffect)
        
        topLabel.font = topLabel.font.withSize(topLabel.font.pointSize - 2)
        bottomLabel.font = bottomLabel.font.withSize(bottomLabel.font.pointSize - 2)

		imageView.layer.cornerRadius = 5
		isAccessibilityElement = true
		accessibilityHint = "Select to copy"
        
        let interaction = UIContextMenuInteraction(delegate: self)
        addInteraction(interaction)
	}
 
	var dropItem: ArchivedDropItem? {
		didSet {
			guard let dropItem = dropItem else { return }
			topLabel.text = dropItem.displayText.0
			bottomLabel.text = todayCellFormatter.string(from: dropItem.updatedAt)
            let size: CGFloat
			switch dropItem.displayMode {
			case .center, .circle:
                size = 18
				imageView.contentMode = .center
			case .fill:
                size = imageView.bounds.width
				imageView.contentMode = .scaleAspectFill
			case .fit:
                size = imageView.bounds.height
				imageView.contentMode = .scaleAspectFit
			}
            var icon = dropItem.displayIcon
            let tint = icon.renderingMode == .alwaysTemplate
            icon = icon.limited(to: CGSize(width: size, height: size), limitTo: 1, useScreenScale: true, singleScale: true)
            if tint {
                icon = icon.withTintColor(imageView.tintColor)
            }
            imageView.image = icon
			accessibilityLabel = "Added " + (bottomLabel.text ?? "")
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

			if !wantMapView && !wantColourView, let e = existingPreviewView {
				e.removeFromSuperview()
				existingPreviewView = nil
			}
		}
	}
}

extension TodayCell: UIContextMenuInteractionDelegate {
    private func createShortcutActions() -> UIMenu? {
        guard let item = dropItem else { return nil }
        
        func makeAction(title: String, callback: @escaping () -> Void, style: UIAction.Attributes, iconName: String?) -> UIAction {
            let a = UIAction(title: title) { _ in callback() }
            a.attributes = style
            if let iconName = iconName {
                a.image = UIImage(systemName: iconName)
            }
            return a
        }
        
        return UIMenu(title: "", image: nil, identifier: nil, options: [], children: [
            
            makeAction(title: "Copy to Clipboard", callback: {
                item.copyToPasteboard()
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(notification: .announcement, argument: "Copied.")
                }
            }, style: [], iconName: "doc.on.doc"),
                        
            makeAction(title: "Reveal in Gladys", callback: { [weak self] in
                if let uuid = self?.dropItem?.uuid.uuidString, let url = URL(string: "gladys://inspect-item/\(uuid)") {
                    NotificationCenter.default.post(name: .OpenParentApp, object: url)
                }
                }, style: [], iconName: "list.bullet.below.rectangle")
        ])
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: 10, height: 10))
        let params = UIDragPreviewParameters()
        params.visiblePath = path
        return UITargetedPreview(view: self, parameters: params)
    }
                
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { [weak self] _ in
            return self?.createShortcutActions()
        })
    }
}
