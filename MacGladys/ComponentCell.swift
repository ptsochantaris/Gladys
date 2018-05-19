//
//  ComponentCell.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 05/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Cocoa

protocol ComponentCellDelegate: class {
	func componentCell(_ componentCell: ComponentCell, wants action: ComponentCell.Action)
}

final class ComponentCell: NSCollectionViewItem {

	enum Action {
		case open, copy, delete, archive, share
	}

	@IBOutlet weak var descriptionLabel: NSTextField!
	@IBOutlet weak var previewLabel: NSTextField!
	@IBOutlet weak var sizeLabel: NSTextField!
	@IBOutlet weak var centreBlock: NSView!
	@IBOutlet weak var spinner: NSProgressIndicator!

	weak var delegate: ComponentCellDelegate?

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
			view.menu = shortcutMenu
		}
	}

	var animateArchiving = false {
		didSet {
			decorate()
		}
	}

	override func viewWillLayout() {
		super.viewWillLayout()
		decorate()
	}

	private var shortcutMenu: NSMenu? {
		guard let item = representedObject as? ArchivedDropItemType else { return nil }
		let m = NSMenu(title: item.displayTitle ?? "")
		m.addItem("Open", action: #selector(openSelected), keyEquivalent: "o", keyEquivalentModifierMask: .command)
		m.addItem("Copy", action: #selector(copySelected), keyEquivalent: "c", keyEquivalentModifierMask: .command)
		m.addItem("Share", action: #selector(shareSelected), keyEquivalent: "s", keyEquivalentModifierMask: [.command, .option])
		if item.isArchivable {
			m.addItem("Archive", action: #selector(archiveSelected), keyEquivalent: "a", keyEquivalentModifierMask: [.command, .option])
		}
		m.addItem(NSMenuItem.separator())
		m.addItem("Delete", action: #selector(deleteSelected), keyEquivalent: String(format: "%c", NSBackspaceCharacter), keyEquivalentModifierMask: .command)
		return m
	}

	override func mouseDown(with event: NSEvent) {
		super.mouseDown(with: event)
		if event.clickCount == 2 {
			openSelected()
		}
	}

	@objc private func openSelected() {
		delegate?.componentCell(self, wants: .open)
	}

	@objc private func copySelected() {
		delegate?.componentCell(self, wants: .copy)
	}

	@objc private func shareSelected() {
		delegate?.componentCell(self, wants: .share)
	}

	@objc private func deleteSelected() {
		delegate?.componentCell(self, wants: .delete)
	}

	@objc private func archiveSelected() {
		delegate?.componentCell(self, wants: .archive)
	}

	private func decorate() {
		guard let typeEntry = representedObject as? ArchivedDropItemType else { return }

		sizeLabel.stringValue = typeEntry.sizeDescription ?? ""
		descriptionLabel.stringValue = "\(typeEntry.typeDescription.uppercased()) (\(typeEntry.typeIdentifier.uppercased()))"
		if animateArchiving {
			spinner.startAnimation(nil)
			previewLabel.isHidden = true
			return
		} else {
			spinner.stopAnimation(nil)
			previewLabel.isHidden = false
		}

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
