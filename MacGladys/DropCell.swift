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

class FirstMouseView: NSView {
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
		return true
	}
}

class FirstMouseImageView: NSImageView {
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
		return true
	}
}

final class TokenTextField: NSTextField {
	var labels: [String]? {
		didSet {

			guard let labels = labels, !labels.isEmpty else {
				attributedStringValue = NSAttributedString()
				return
			}

			let p = NSMutableParagraphStyle()
			p.alignment = alignment
			p.lineBreakMode = .byWordWrapping
			p.lineSpacing = 3

			let separator = "   "

			let string = NSMutableAttributedString(string: labels.joined(separator: separator), attributes: [
				NSAttributedStringKey.font: font!,
				NSAttributedStringKey.foregroundColor: #colorLiteral(red: 0.5924374461, green: 0.09241057187, blue: 0.07323873788, alpha: 1),
				NSAttributedStringKey.paragraphStyle: p,
				NSAttributedStringKey.baselineOffset: -2,
				])

			var start = 0
			for label in labels {
				let len = label.count
				string.addAttribute(NSAttributedStringKey("HighlightText"), value: 1, range: NSMakeRange(start, len))
				start += len + separator.count
			}
			attributedStringValue = string
			setNeedsDisplay()
		}
	}

	override var intrinsicContentSize: NSSize {
		var s = super.intrinsicContentSize
		s.height += 2
		return s
	}

	override func draw(_ dirtyRect: NSRect) {

		guard !attributedStringValue.string.isEmpty, let labels = labels, let context = NSGraphicsContext.current?.cgContext else { return }

		let highlightColor = #colorLiteral(red: 0.5924374461, green: 0.09241057187, blue: 0.07323873788, alpha: 1)

		let framesetter = CTFramesetterCreateWithAttributedString(attributedStringValue)

		let path = CGMutablePath()
		path.addRect(dirtyRect)

		let totalFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)

		context.textMatrix = .identity
		context.translateBy(x: 0, y: dirtyRect.size.height)
		context.scaleBy(x: 1, y: -1)

		if labels.count > 0 {

			let lines = CTFrameGetLines(totalFrame) as NSArray
			let lineCount = lines.count

			for index in 0 ..< lineCount {
				let line = lines[index] as! CTLine

				var origins = [CGPoint](repeating: .zero, count: lineCount)
				CTFrameGetLineOrigins(totalFrame, CFRangeMake(0, 0), &origins)
				let lineFrame = CTLineGetBoundsWithOptions(line, [])
				let offset: CGFloat = index < (lineCount-1) ? 2 : -6
				let lineStart = (dirtyRect.width - lineFrame.width + offset) * 0.5

				for r in CTLineGetGlyphRuns(line) as NSArray {

					let run = r as! CTRun
					let attributes = CTRunGetAttributes(run) as NSDictionary

					if attributes["HighlightText"] != nil {
						var runBounds = lineFrame

						runBounds.size.width = CGFloat(CTRunGetTypographicBounds(run, CFRangeMake(0, 0), nil, nil ,nil)) + 6
						runBounds.origin.x = lineStart + CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, nil)
						runBounds.origin.y = origins[index].y - 4.5

						context.setStrokeColor(highlightColor.withAlphaComponent(0.7).cgColor)
						context.setLineWidth(0.5)
						context.addPath(CGPath(roundedRect: runBounds, cornerWidth: 3, cornerHeight: 3, transform: nil))
						context.strokePath()
					}
				}
			}
		}

		CTFrameDraw(totalFrame, context)
	}
}

final class MiniMapView: FirstMouseView {

	private var coordinate: CLLocationCoordinate2D?
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
		if let existingImage = imageCache.object(forKey: cacheKey) {
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
				imageCache.setObject(img, forKey: cacheKey)
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
}

final class ColourView: FirstMouseView {}

extension NSMenu {
	func addItem(_ title: String, action: Selector, keyEquivalent: String, keyEquivalentModifierMask: NSEvent.ModifierFlags) {
		let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
		menuItem.keyEquivalentModifierMask = keyEquivalentModifierMask
		addItem(menuItem)
	}
}

final class DropCell: NSCollectionViewItem, NSMenuDelegate {

	@IBOutlet private weak var topLabel: NSTextField!
	@IBOutlet private weak var bottomLabel: NSTextField!
	@IBOutlet private weak var image: FirstMouseView!
	@IBOutlet private weak var progressView: NSProgressIndicator!
	@IBOutlet private weak var cancelButton: NSButton!
	@IBOutlet private weak var lockImage: NSImageView!
	@IBOutlet private weak var labelTokenField: TokenTextField!
	@IBOutlet private weak var sharedIcon: NSImageView!
	
	private var existingPreviewView: FirstMouseView?

	private static let shareImage: NSImage = {
		let image = #imageLiteral(resourceName: "iconUserCheckedSmall").copy() as! NSImage
		image.isTemplate = false
		image.lockFocus()
		#colorLiteral(red: 0.8431372549, green: 0.831372549, blue: 0.8078431373, alpha: 1).set()

		let imageRect = NSRect(origin: NSZeroPoint, size: image.size)
		imageRect.fill(using: .sourceAtop)
		image.unlockFocus()
		return image
	}()

	private static let shareImageTinted: NSImage = {
		let image = #imageLiteral(resourceName: "iconUserCheckedSmall").copy() as! NSImage
		image.isTemplate = false
		image.lockFocus()
		#colorLiteral(red: 0.5924374461, green: 0.09241057187, blue: 0.07323873788, alpha: 1).set()

		let imageRect = NSRect(origin: NSZeroPoint, size: image.size)
		imageRect.fill(using: .sourceAtop)
		image.unlockFocus()
		return image
	}()

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
			representedObject = notification.object
			reDecorate()
		}
	}

	private var archivedDropItem: ArchivedDropItem? {
		return representedObject as? ArchivedDropItem
	}

	override var representedObject: Any? {
		didSet {
			view.needsLayout = true
		}
	}

	private var shortcutMenu: NSMenu? {
		guard let item = archivedDropItem else { return nil }
		if item.needsUnlock {
			let m = NSMenu()
			m.addItem("Unlock", action: #selector(unlockSelected), keyEquivalent: "", keyEquivalentModifierMask: [])
			m.addItem("Remove Lock", action: #selector(removeLockSelected), keyEquivalent: "", keyEquivalentModifierMask: [])
			m.delegate = self
			return m
		} else {
			let m = NSMenu(title: item.displayTitleOrUuid)
			m.addItem("Get Info", action: #selector(infoSelected), keyEquivalent: "i", keyEquivalentModifierMask: .command)
			m.addItem("Open", action: #selector(openSelected), keyEquivalent: "o", keyEquivalentModifierMask: .command)
			m.addItem("Move to Top", action: #selector(topSelected), keyEquivalent: "m", keyEquivalentModifierMask: .command)
			m.addItem("Copy", action: #selector(copySelected), keyEquivalent: "c", keyEquivalentModifierMask: .command)
			m.addItem("Share", action: #selector(shareSelected), keyEquivalent: "s", keyEquivalentModifierMask: [.command, .option])
			if !item.isImportedShare {
				m.addItem(NSMenuItem.separator())
				m.addItem("Lock", action: #selector(lockSelected), keyEquivalent: "", keyEquivalentModifierMask: [])
				m.addItem(NSMenuItem.separator())
				m.addItem("Delete", action: #selector(deleteSelected), keyEquivalent: String(format: "%c", NSBackspaceCharacter), keyEquivalentModifierMask: .command)
			}
			m.delegate = self
			return m
		}
	}

	override func viewWillLayout() {
		super.viewWillLayout()
		reDecorate()
	}

	private func reDecorate() {
		let item = archivedDropItem

		var wantColourView = false
		var wantMapView = false
		var hideCancel = true
		var hideImage = true
		var hideLock = true
		var hideLabels = true
		var share = ArchivedDropItem.ShareMode.none

		var topLabelText = ""
		var topLabelAlignment = NSTextAlignment.center

		var bottomLabelText = ""
		var bottomLabelHighlight = false
		var bottomLabelAlignment = NSTextAlignment.center

		let showLoading = item?.shouldDisplayLoading ?? false
		if showLoading {
			progressView.startAnimation(nil)
		} else {
			progressView.stopAnimation(nil)
		}

		view.menu = shortcutMenu

		if let item = item {

			if showLoading {
				hideCancel = false
				image.layer?.contents = nil

			} else if item.needsUnlock {
				hideLock = false
				image.layer?.contents = nil
				bottomLabelAlignment = .center
				bottomLabelText = item.lockHint ?? ""

			} else {

				hideImage = false
				share = item.shareMode

				let cacheKey = item.imageCacheKey
				if let cachedImage = imageCache.object(forKey: cacheKey) {
					image.layer?.contents = cachedImage
				} else {
					image.layer?.contents = nil
					imageProcessingQueue.async { [weak self] in
						if let u1 = self?.archivedDropItem?.uuid, u1 == item.uuid {
							let img = item.displayIcon
							imageCache.setObject(img, forKey: cacheKey)
							DispatchQueue.main.sync { [weak self] in
								if let u2 = self?.archivedDropItem?.uuid, u1 == u2 {
									self?.image.layer?.contents = img
								}
							}
						}
					}
				}


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

				if PersistedOptions.displayLabelsInMainView && !item.labels.isEmpty {
					hideLabels = false
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
					primaryLabel.maximumNumberOfLines = 6
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
					image.layer?.contentsGravity = kCAGravityResizeAspectFill
					primaryLabel.maximumNumberOfLines = 6
					secondaryLabel.maximumNumberOfLines = 2
				}

				// if we're showing an icon, let's try to enhance things a bit
				if image.layer?.contentsGravity == kCAGravityCenter, let backgroundItem = item.backgroundInfoObject {
					if let mapItem = backgroundItem as? MKMapItem {
						wantMapView = true
						if let m = existingPreviewView as? MiniMapView {
							m.show(location: mapItem)
						} else {
							if let m = existingPreviewView {
								m.removeFromSuperview()
							}
							let m = MiniMapView(at: mapItem)
							m.translatesAutoresizingMaskIntoConstraints = false
							image.addSubview(m)
							NSLayoutConstraint.activate([
								m.leadingAnchor.constraint(equalTo: image.leadingAnchor),
								m.trailingAnchor.constraint(equalTo: image.trailingAnchor),
								m.topAnchor.constraint(equalTo: image.topAnchor),
								m.bottomAnchor.constraint(equalTo: image.bottomAnchor)
								])

							existingPreviewView = m
						}
					} else if let colourItem = backgroundItem as? NSColor {
						wantColourView = true
						if let m = existingPreviewView as? ColourView {
							m.layer?.backgroundColor = colourItem.cgColor
						} else {
							if let m = existingPreviewView {
								m.removeFromSuperview()
							}
							let m = ColourView()
							m.wantsLayer = true
							m.layer?.backgroundColor = colourItem.cgColor
							m.translatesAutoresizingMaskIntoConstraints = false
							image.addSubview(m)
							NSLayoutConstraint.activate([
								m.leadingAnchor.constraint(equalTo: image.leadingAnchor),
								m.trailingAnchor.constraint(equalTo: image.trailingAnchor),
								m.topAnchor.constraint(equalTo: image.topAnchor),
								m.bottomAnchor.constraint(equalTo: image.bottomAnchor)
								])

							existingPreviewView = m
						}
					}
				}
			}

		} else { // item is nil
			image.layer?.contents = nil
		}

		if !(wantMapView || wantColourView), let e = existingPreviewView {
			e.removeFromSuperview()
			existingPreviewView = nil
		}

		labelTokenField.isHidden = hideLabels
		labelTokenField.labels = item?.labels

		topLabel.stringValue = topLabelText
		topLabel.isHidden = topLabelText.isEmpty
		topLabel.alignment = topLabelAlignment

		bottomLabel.stringValue = bottomLabelText
		bottomLabel.isHidden = bottomLabelText.isEmpty
		bottomLabel.alignment = bottomLabelAlignment
		bottomLabel.textColor = bottomLabelHighlight ? ViewController.tintColor : ViewController.labelColor

		image.isHidden = hideImage
		cancelButton.isHidden = hideCancel
		progressView.isHidden = hideCancel
		lockImage.isHidden = hideLock

		switch share {
		case .none:
			sharedIcon.image = nil
			sharedIcon.isHidden = true
		case .elsewhereReadOnly, .elsewhereReadWrite:
			sharedIcon.image = DropCell.shareImage
			sharedIcon.isHidden = false
		case .sharing:
			sharedIcon.image = DropCell.shareImageTinted
			sharedIcon.isHidden = false
		}
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

	@objc private func topSelected() {
		ViewController.shared.moveToTop(self)
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

	@IBAction private func cancelSelected(_ sender: NSButton) {
		if let archivedDropItem = archivedDropItem, archivedDropItem.shouldDisplayLoading {
			ViewController.shared.deleteRequested(for: [archivedDropItem])
		}
	}

	func menuWillOpen(_ menu: NSMenu) {
		ViewController.shared.addCellToSelection(self)
	}

	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.title {
		case "Lock", "Unlock", "Remove Lock":
			return ViewController.shared.itemView.selectionIndexPaths.count == 1 && (archivedDropItem?.isImportedShare ?? false)
		default:
			return true
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
