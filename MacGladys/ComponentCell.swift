//
//  ComponentCell.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 05/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

final class ComponentCell: NSCollectionViewItem {
	@IBOutlet weak var descriptionLabel: NSTextField!
	@IBOutlet weak var previewLabel: NSTextField!
	@IBOutlet weak var sizeLabel: NSTextField!
	@IBOutlet weak var centreBlock: NSView!

	override func viewDidLoad() {
		super.viewDidLoad()
		view.layer?.cornerRadius = 8
		view.layer?.backgroundColor = NSColor.white.cgColor
		centreBlock.layer?.cornerRadius = 4
		centreBlock.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
	}

	override var representedObject: Any? {
		didSet {
			decorate()
		}
	}

	override func viewWillLayout() {
		super.viewWillLayout()
		decorate()
	}

	private func decorate() {
		guard let typeEntry = representedObject as? ArchivedDropItemType else { return }

		if let title = typeEntry.displayTitle ?? typeEntry.accessoryTitle ?? typeEntry.encodedUrl?.path {
			previewLabel.alphaValue = 1.0
			previewLabel.stringValue = "\"\(title)\""
			previewLabel.alignment = typeEntry.displayTitleAlignment
		} else if typeEntry.dataExists {
			previewLabel.alphaValue = 0.7
			if typeEntry.typeIdentifier == "com.apple.webarchive" {
				previewLabel.stringValue = ComponentCell.shortFormatter.string(from: typeEntry.createdAt)
			} else {
				previewLabel.stringValue = "Binary Data"
			}
			previewLabel.alignment = .center
		} else {
			previewLabel.alphaValue = 0.7
			previewLabel.stringValue = "Loading Error"
			previewLabel.alignment = .center
		}
		sizeLabel.stringValue = typeEntry.sizeDescription ?? ""
		descriptionLabel.stringValue = "\(typeEntry.contentDescription.uppercased()) (\(typeEntry.typeIdentifier.uppercased()))"
	}

	private static let shortFormatter: DateFormatter = {
		let d = DateFormatter()
		d.doesRelativeDateFormatting = true
		d.dateStyle = .short
		d.timeStyle = .short
		return d
	}()

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
}
