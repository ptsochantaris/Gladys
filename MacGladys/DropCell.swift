//
//  DropCell.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 29/04/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation
import Cocoa
import MapKit

final class MiniMapView: NSImageView {

	private var coordinate: CLLocationCoordinate2D?
	private static let cache = NSCache<NSString, NSImage>()
	private weak var snapshotter: MKMapSnapshotter?
	private var snapshotOptions: MKMapSnapshotOptions?

	func show(location: MKMapItem) {

		let newCoordinate = location.placemark.coordinate
		if let coordinate = coordinate,
			newCoordinate.latitude == coordinate.latitude,
			newCoordinate.longitude == coordinate.longitude { return }

		image = nil
		coordinate = newCoordinate
	}

	init(at location: MKMapItem) {
		super.init(frame: .zero)
		//imageScaling = .scaleNone
		show(location: location)
	}

	override func layout() {
		super.layout()

		guard let coordinate = coordinate else { return }
		if bounds.isEmpty { return }
		if let image = image, image.size == bounds.size { return }

		let cacheKey = NSString(format: "%f %f %f %f", coordinate.latitude, coordinate.longitude, bounds.size.width, bounds.size.height)
		if let existingImage = MiniMapView.cache.object(forKey: cacheKey) {
			image = existingImage
			return
		}

		if let o = snapshotOptions {
			if !(o.region.center.latitude != coordinate.latitude || o.region.center.longitude != coordinate.longitude || o.size != bounds.size) {
				return
			}
		}

		isHidden = true
		snapshotter?.cancel()
		snapshotter = nil
		snapshotOptions = nil

		let O = MKMapSnapshotOptions()
		O.region = MKCoordinateRegionMakeWithDistance(coordinate, 200.0, 200.0)
		O.showsBuildings = true
		O.showsPointsOfInterest = true
		O.size = bounds.size
		snapshotOptions = O

		let S = MKMapSnapshotter(options: O)
		snapshotter = S

		S.start { snapshot, error in
			if let snapshot = snapshot {
				let img = snapshot.image
				MiniMapView.cache.setObject(img, forKey: cacheKey)
				DispatchQueue.main.async { [weak self] in
					self?.image = img
					self?.isHidden = false
				}
			}
			if let error = error {
				log("Error taking snapshot: \(error.finalDescription)")
			}
		}
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	static func clearCaches() {
		cache.removeAllObjects()
	}
}

final class DropCell: NSCollectionViewItem {

	@IBOutlet weak var topLabel: NSTextField!
	@IBOutlet weak var bottomLabel: NSTextField!
	@IBOutlet weak var image: NSView!
	@IBOutlet weak var progressView: NSProgressIndicator!
	@IBOutlet weak var cancelHolder: NSView!
	@IBOutlet weak var lockImage: NSImageView!
	@IBOutlet weak var mergeImage: NSImageView!

	var mergeMode = false
	private var existingMapView: MiniMapView?

	override func viewDidLoad() {
		super.viewDidLoad()
		view.layer?.cornerRadius = 10
		view.layer?.backgroundColor = .white
		topLabel.maximumNumberOfLines = 2
		bottomLabel.maximumNumberOfLines = 2
		image.layer?.cornerRadius = 5
		image.layer?.backgroundColor = #colorLiteral(red: 0.8431372549, green: 0.831372549, blue: 0.8078431373, alpha: 1)
	}

	private var archivedDropItem: ArchivedDropItem? {
		return representedObject as? ArchivedDropItem
	}

	private var shortcutMenu: NSMenu? {
		guard let item = archivedDropItem else { return nil }
		let m = NSMenu(title: item.displayTitleOrUuid)
		m.addItem(withTitle: "Copy", action: #selector(copySelected), keyEquivalent: "")
		m.addItem(withTitle: "Delete", action: #selector(deleteSelected), keyEquivalent: "")
		return m
	}

	override func viewWillLayout() {
		super.viewWillLayout()

		let item = archivedDropItem

		var wantMapView = false
		var hideCancel = true
		var hideImage = true
		var hideLock = true
		var hideMerge = true

		var topLabelText = ""
		var topLabelAlignment = NSTextAlignment.center

		var bottomLabelText = ""
		var bottomLabelHighlight = false
		var bottomLabelAlignment = NSTextAlignment.center

		if item?.loadingProgress != nil {
			progressView.startAnimation(nil)
		} else {
			progressView.stopAnimation(nil)
		}

		view.menu = shortcutMenu

		if let item = item {

			if item.shouldDisplayLoading {
				hideCancel = false
				image.layer?.contents = nil

			} else if item.needsUnlock {
				hideLock = false
				image.layer?.contents = nil
				bottomLabelAlignment = .center
				bottomLabelText = item.lockHint ?? ""

			} else if mergeMode {
				hideMerge = false
				hideImage = true
				image.layer?.contents = nil
				topLabelAlignment = .center
				topLabelText = "Add data component"

			} else {

				hideImage = false

				image.layer?.contents = item.displayIcon

				let primaryLabel: NSTextField
				let secondaryLabel: NSTextField

				let titleInfo = item.displayText
				topLabelAlignment = titleInfo.1
				topLabelText = titleInfo.0 ?? ""

				if PersistedOptions.displayNotesInMainView && !item.note.isEmpty {
					bottomLabelText = item.note
					bottomLabelHighlight = true
				} else if let url = item.associatedWebURL {
					bottomLabelText = url.absoluteString
					if topLabelText == bottomLabelText {
						topLabelText = ""
					}
				}

				if bottomLabelText.isEmpty && !topLabelText.isEmpty {
					bottomLabelText = topLabelText
					bottomLabelAlignment = topLabelAlignment
					topLabelText = ""

					primaryLabel = bottomLabel
					secondaryLabel = topLabel
				} else {
					primaryLabel = topLabel
					secondaryLabel = bottomLabel
				}

				switch item.displayMode {
				case .center:
					image.layer?.contentsGravity = kCAGravityCenter
					primaryLabel.maximumNumberOfLines = 8
					secondaryLabel.maximumNumberOfLines = 2
				case .fill:
					image.layer?.contentsGravity = kCAGravityResizeAspectFill
					primaryLabel.maximumNumberOfLines = 6
					secondaryLabel.maximumNumberOfLines = 2
				case .fit:
					image.layer?.contentsGravity = kCAGravityResizeAspect
					primaryLabel.maximumNumberOfLines = 6
					secondaryLabel.maximumNumberOfLines = 2
				case .circle:
					image.layer?.contentsGravity = kCAGravityResize
					primaryLabel.maximumNumberOfLines = 6
					secondaryLabel.maximumNumberOfLines = 2
				}

				// if we're showing an icon, let's try to enhance things a bit
				if image.layer?.contentsGravity == kCAGravityCenter, let backgroundItem = item.backgroundInfoObject {
					if let mapItem = backgroundItem as? MKMapItem {
						wantMapView = true
						if let m = existingMapView {
							m.show(location: mapItem)
						} else {
							let m = MiniMapView(at: mapItem)
							m.translatesAutoresizingMaskIntoConstraints = false
							image.addSubview(m)
							NSLayoutConstraint.activate([
								m.leadingAnchor.constraint(equalTo: image.leadingAnchor),
								m.trailingAnchor.constraint(equalTo: image.trailingAnchor),
								m.topAnchor.constraint(equalTo: image.topAnchor),
								m.bottomAnchor.constraint(equalTo: image.bottomAnchor)
								])

							existingMapView = m
						}
					}
				}
			}

		} else { // item is nil
			image.layer?.contents = nil
		}

		if !wantMapView, let e = existingMapView {
			e.removeFromSuperview()
			existingMapView = nil
		}

		topLabel.stringValue = topLabelText
		topLabel.isHidden = topLabelText.isEmpty
		topLabel.alignment = topLabelAlignment

		bottomLabel.stringValue = bottomLabelText
		bottomLabel.isHidden = bottomLabelText.isEmpty
		bottomLabel.alignment = bottomLabelAlignment
		bottomLabel.textColor = bottomLabelHighlight ? ViewController.tintColor : ViewController.labelColor

		image.isHidden = hideImage
		cancelHolder.isHidden = hideCancel
		lockImage.isHidden = hideLock
		mergeImage.isHidden = hideMerge
	}

	@objc private func copySelected() {
		ViewController.shared.copy(nil)
	}

	@objc private func deleteSelected() {
		ViewController.shared.delete(nil)
	}

	@IBAction func cancelSelected(_ sender: NSButton) {
		if let archivedDropItem = archivedDropItem, archivedDropItem.shouldDisplayLoading {
			ViewController.shared.deleteRequested(for: [archivedDropItem])
		}
	}

	override var isSelected: Bool {
		didSet {
			guard let l = view.layer else { return }
			if isSelected {
				l.borderColor = ViewController.tintColor.cgColor
				l.borderWidth = 2
			} else {
				l.borderColor = NSColor.clear.cgColor
				l.borderWidth = 0
			}
		}
	}

	override func mouseDown(with event: NSEvent) {
		super.mouseDown(with: event)
		if event.clickCount == 2 {
			ViewController.shared.selected()
		}
	}
}
