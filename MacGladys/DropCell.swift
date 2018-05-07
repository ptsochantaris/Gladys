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

final class MiniMapView: NSView {

	private var coordinate: CLLocationCoordinate2D?
	private static let cache = NSCache<NSString, NSImage>()
	private weak var snapshotter: MKMapSnapshotter?
	private var snapshotOptions: MKMapSnapshotOptions?

	func show(location: MKMapItem) {

		let newCoordinate = location.placemark.coordinate
		if let coordinate = coordinate,
			newCoordinate.latitude == coordinate.latitude,
			newCoordinate.longitude == coordinate.longitude { return }

		layer?.contents = nil
		coordinate = newCoordinate
		go()
	}

	init(at location: MKMapItem) {
		super.init(frame: .zero)
		wantsLayer = true
		layer?.contentsGravity = kCAGravityResizeAspectFill
		show(location: location)
	}

	private func go() {
		guard let coordinate = coordinate else { return }

		let cacheKey = NSString(format: "%f %f", coordinate.latitude, coordinate.longitude)
		if let existingImage = MiniMapView.cache.object(forKey: cacheKey) {
			layer?.contents = existingImage
			return
		}

		if let o = snapshotOptions {
			if !(o.region.center.latitude != coordinate.latitude || o.region.center.longitude != coordinate.longitude) {
				return
			}
		}

		snapshotter?.cancel()
		snapshotter = nil
		snapshotOptions = nil

		let O = MKMapSnapshotOptions()
		O.region = MKCoordinateRegionMakeWithDistance(coordinate, 200.0, 200.0)
		O.showsBuildings = true
		O.showsPointsOfInterest = true
		O.size = NSSize(width: 512, height: 512)
		snapshotOptions = O

		let S = MKMapSnapshotter(options: O)
		snapshotter = S

		S.start { snapshot, error in
			if let snapshot = snapshot {
				let img = snapshot.image
				MiniMapView.cache.setObject(img, forKey: cacheKey)
				DispatchQueue.main.async { [weak self] in
					self?.layer?.contents = img
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

extension NSMenu {
	func addItem(_ title: String, action: Selector, keyEquivalent: String, keyEquivalentModifierMask: NSEvent.ModifierFlags) {
		let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
		menuItem.keyEquivalentModifierMask = keyEquivalentModifierMask
		addItem(menuItem)
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

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(itemModified(_:)), name: .ItemModified, object: nil)
	}

	@objc private func itemModified(_ notification: Notification) {
		if (notification.object as? ArchivedDropItem) == archivedDropItem {
			reDecorate()
		}
	}

	private var archivedDropItem: ArchivedDropItem? {
		return representedObject as? ArchivedDropItem
	}

	private var shortcutMenu: NSMenu? {
		guard let item = archivedDropItem else { return nil }
		if item.needsUnlock {
			let m = NSMenu()
			m.addItem("Unlock", action: #selector(unlockSelected), keyEquivalent: "", keyEquivalentModifierMask: [])
			m.addItem("Remove Lock", action: #selector(removeLockSelected), keyEquivalent: "", keyEquivalentModifierMask: [])
			return m
		} else {
			let m = NSMenu(title: item.displayTitleOrUuid)
			m.addItem("Open", action: #selector(openSelected), keyEquivalent: "o", keyEquivalentModifierMask: .command)
			m.addItem("Get Info", action: #selector(infoSelected), keyEquivalent: "i", keyEquivalentModifierMask: .command)
			m.addItem("Copy", action: #selector(copySelected), keyEquivalent: "c", keyEquivalentModifierMask: .command)
			m.addItem("Share", action: #selector(shareSelected), keyEquivalent: "s", keyEquivalentModifierMask: [.command, .option])
			m.addItem("Lock", action: #selector(lockSelected), keyEquivalent: "", keyEquivalentModifierMask: [])
			m.addItem(NSMenuItem.separator())
			m.addItem("Delete", action: #selector(deleteSelected), keyEquivalent: String(format: "%c", NSBackspaceCharacter), keyEquivalentModifierMask: .command)
			return m
		}
	}

	override func viewWillLayout() {
		super.viewWillLayout()
		reDecorate()
	}

	private func reDecorate() {
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

	@objc private func infoSelected() {
		ViewController.shared.info(self)
	}

	@objc private func openSelected() {
		ViewController.shared.open(self)
	}

	@objc private func copySelected() {
		ViewController.shared.copy(self)
	}

	@objc private func lockSelected() {
		ViewController.shared.createLock(self)
	}

	@objc private func shareSelected() {
		ViewController.shared.shareSelected(self)
	}

	@objc private func unlockSelected() {
		ViewController.shared.unlock(self)
	}

	@objc private func removeLockSelected() {
		ViewController.shared.removeLock(self)
	}

	@objc private func deleteSelected() {
		ViewController.shared.delete(self)
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
			if let a = archivedDropItem, a.needsUnlock {
				ViewController.shared.unlock(self)
			} else {
				ViewController.shared.info(self)
			}
		}
	}
}
