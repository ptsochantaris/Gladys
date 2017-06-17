//
//  ViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 16/06/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import MapKit

protocol LoadCompletionDelegate: class {
	func loadCompleted(success: Bool)
}

final class ArchivedDropItemType {

	let typeIdentifier: String
	var classType: ClassType?

	private var bytes: Data?
	private let folderUrl: URL
	private let uuid = UUID()

	private weak var delegate: LoadCompletionDelegate?
	private var loadCount = 0
	private var allLoadedWell = true

	func setBytes(object: Any, classType: ClassType) {
		let d = NSMutableData()
		let k = NSKeyedArchiver(forWritingWith: d)
		k.encode(object, forKey: classType.rawValue)
		k.finishEncoding()
		self.bytes = d as Data
		self.classType = classType
	}

	enum ClassType: String {
		case NSString, NSAttributedString, UIColor, UIImage, NSData, MKMapItem, NSURL
	}

	init(provider: NSItemProvider, typeIdentifier: String, parentUrl: URL, delegate: LoadCompletionDelegate) {
		self.typeIdentifier = typeIdentifier
		self.delegate = delegate
		self.folderUrl = parentUrl.appendingPathComponent(uuid.uuidString)

		provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
			if let item = item {
				let receivedTypeString = type(of: item)
				NSLog("name: [\(provider.suggestedName ?? "")] type: [\(typeIdentifier)] class: [\(receivedTypeString)]")
			}

			if let item = item as? NSString {
				NSLog("      received string: \(item)")
				self.setBytes(object: item, classType: .NSString)
				self.signalDone()

			} else if let item = item as? NSAttributedString {
				NSLog("      received attributed string: \(item)")
				self.setBytes(object: item, classType: .NSAttributedString)
				self.signalDone()

			} else if let item = item as? UIColor {
				NSLog("      received color: \(item)")
				self.setBytes(object: item, classType: .UIColor)
				self.signalDone()

			} else if let item = item as? UIImage {
				NSLog("      received image: \(item)")
				self.setBytes(object: item, classType: .UIImage)
				self.signalDone()

			} else if let item = item as? Data {
				NSLog("      received data: \(item)")
				self.classType = .NSData
				self.bytes = item
				self.signalDone()

			} else if let item = item as? MKMapItem {
				NSLog("      received map item: \(item)")
				self.setBytes(object: item, classType: .MKMapItem)
				self.signalDone()

			} else if let item = item as? URL {
				if item.scheme == "file" {
					NSLog("      will duplicate item at local url: \(item)")
					provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isLocal, error in
						if let url = url {
							NSLog("      received local url: \(url)")
							let localUrl = self.copyLocal(url)
							self.setBytes(object: localUrl, classType: .NSURL)
							self.signalDone()

						} else if let error = error {
							NSLog("Error fetching local url file representation: \(error.localizedDescription)")
							self.allLoadedWell = false
							self.signalDone()
						}
					}
				} else {
					NSLog("      received remote url: \(item)")
					self.setBytes(object: item, classType: .NSURL)
					self.signalDone()
				}

			} else if let error = error {
				NSLog("      error receiving item: \(error.localizedDescription)")
				self.allLoadedWell = false
				self.signalDone()


			} else {
				NSLog("      unknown class")
				self.allLoadedWell = false
				self.signalDone()
				// TODO: generate analyitics report to record what type was received and what UTI
			}
		}
	}

	private func signalDone() {
		DispatchQueue.main.async {
			self.delegate?.loadCompleted(success: self.allLoadedWell)
		}
	}

	private func copyLocal(_ url: URL) -> URL {
		let f = FileManager.default
		if f.fileExists(atPath: folderUrl.path) {
			try! f.removeItem(at: folderUrl)
		}
		try! f.createDirectory(at: folderUrl, withIntermediateDirectories: true, attributes: nil)
		let newUrl = folderUrl.appendingPathComponent(url.lastPathComponent)
		try! f.copyItem(at: url, to: newUrl)
		return newUrl
	}

	lazy var loadHandler: NSItemProvider.LoadHandler = { completion, requestedClassType, options in

		if let data = self.bytes, let classType = self.classType {

			if requestedClassType != nil {
				let requestedClassName = NSStringFromClass(requestedClassType)
				if requestedClassName == "NSData" {
					completion(data as NSData, nil)
					return
				}
			}

			let u = NSKeyedUnarchiver(forReadingWith: data)
			let item = u.decodeObject(of: [NSClassFromString(classType.rawValue)!], forKey: classType.rawValue) as? NSSecureCoding
			let finalName = String(describing: item)
			NSLog("Responding with \(finalName)")
			completion(item ?? (data as NSData), nil)

		} else {
			completion(nil, nil)
		}
	}

	var displayIcon: UIImage? {
		if let data = self.bytes {
			if classType == .UIImage {
				let u = NSKeyedUnarchiver(forReadingWith: data)
				return u.decodeObject(of: [UIImage.self], forKey: ClassType.UIImage.rawValue) as? UIImage
			} else if typeIdentifier == "public.png" || typeIdentifier == "public.jpeg" {
				if classType == .NSURL {
					let u = NSKeyedUnarchiver(forReadingWith: data)
					if let url = u.decodeObject(of: [NSURL.self], forKey: ClassType.NSURL.rawValue) as? NSURL, let path = url.path {
						return UIImage(contentsOfFile: path)
					} else {
						return nil
					}
				} else if classType == .NSData {
					return UIImage(data: data)
				}
			}
		}
		return nil
	}

	var displayTitle: String? {
		if let data = self.bytes {
			if classType == .NSString {
				let u = NSKeyedUnarchiver(forReadingWith: data)
				if let res = u.decodeObject(of: [NSString.self], forKey: ClassType.NSString.rawValue) as? String {
					return res
				}
			} else if classType == .NSAttributedString {
				let u = NSKeyedUnarchiver(forReadingWith: data)
				let a = u.decodeObject(of: [NSAttributedString.self], forKey: ClassType.NSAttributedString.rawValue) as? NSAttributedString
				if let res = a?.string {
					return res
				}
			} else if classType == .NSURL {
				let u = NSKeyedUnarchiver(forReadingWith: data)
				let a = u.decodeObject(of: [NSURL.self], forKey: ClassType.NSURL.rawValue) as? NSURL
				if let res = a?.absoluteString {
					return res
				}
			} else if typeIdentifier == "public.utf8-plain-text" {
				return String(data: data, encoding: .utf8)
			} else if typeIdentifier == "public.utf16-plain-text" {
				return String(data: data, encoding: .utf16)
			}
		}
		return nil

	}
}

final class ArchivedDropItem: LoadCompletionDelegate {

	let uuid = UUID()
	let suggestedName: String?
	var typeItems: [ArchivedDropItemType]!

	weak var delegate: LoadCompletionDelegate?
	private var loadCount = 0
	private var allLoadedWell = true
	func loadCompleted(success: Bool) {
		if !success { allLoadedWell = false }
		loadCount = loadCount - 1
		if loadCount == 0 {
			delegate?.loadCompleted(success: allLoadedWell)
		}
	}

	var displayIcon: UIImage? {
		for i in typeItems {
			if let img = i.displayIcon {
				return img
			}
		}
		return nil
	}

	var displayTitle: String? {
		if let suggestedName = suggestedName {
			return suggestedName
		}
		for i in typeItems {
			if let title = i.displayTitle {
				return title
			}
		}
		return nil
	}

	var myURL: URL {
		let f = FileManager.default
		let docs = f.urls(for: .documentDirectory, in: .userDomainMask).first!
		return docs.appendingPathComponent(uuid.uuidString)
	}

	init(provider: NSItemProvider, delegate: LoadCompletionDelegate) {
		self.delegate = delegate
		suggestedName = provider.suggestedName
		loadCount = provider.registeredTypeIdentifiers.count
		typeItems = provider.registeredTypeIdentifiers.map { ArchivedDropItemType(provider: provider, typeIdentifier: $0, parentUrl: myURL, delegate: self) }
	}

	var itemProvider: NSItemProvider {
		let p = NSItemProvider()
		p.suggestedName = suggestedName
		for item in typeItems {
			p.registerItem(forTypeIdentifier: item.typeIdentifier, loadHandler: item.loadHandler)
		}
		return p
	}
}

final class ArchivedDrop: LoadCompletionDelegate {

	private let uuid = UUID()
	private let createdAt = Date()
	private var items: [ArchivedDropItem]!

	var displayIcon: UIImage {
		for i in items {
			if let img = i.displayIcon {
				return img
			}
		}
		return #imageLiteral(resourceName: "iconStickyNote") // TODO: use image element from items, if available, or possibly draw from text elements
	}

	var displayTitle: String {
		if isLoading {
			return "..."
		}

		for i in items {
			if let title = i.displayTitle {
				return title
			}
		}
		return "\(createdAt.timeIntervalSinceReferenceDate)" // TODO
	}

	weak var delegate: LoadCompletionDelegate?
	private var loadCount = 0
	private var allLoadedWell = true
	var isLoading = true
	func loadCompleted(success: Bool) {
		if !success { allLoadedWell = false }
		loadCount = loadCount - 1
		if loadCount == 0 {
			isLoading = false
			delegate?.loadCompleted(success: allLoadedWell)
		}
	}

	var dragItems: [UIDragItem] {
		return items.map {
			let i = UIDragItem(itemProvider: $0.itemProvider)
			i.localObject = self
			return i
		}
	}

	init(session: UIDropSession) {

		let progressType = session.progressIndicatorStyle
		NSLog("Should display progress: \(progressType)")

		loadCount = session.items.count
		items = session.items.map {
			if let item = ($0.localObject as? ArchivedDropItem) {
				item.delegate = self
				return item
			} else {
				return ArchivedDropItem(provider: $0.itemProvider, delegate: self)
			}
		}
	}
}

final class ArchivedItemCell: UICollectionViewCell, LoadCompletionDelegate {
	@IBOutlet weak var image: UIImageView!
	@IBOutlet weak var label: UILabel!

	var archivedDrop: ArchivedDrop? {
		didSet {
			oldValue?.delegate = nil
			if archivedDrop?.isLoading ?? true {
				image.isHidden = true
			} else {
				image.image = archivedDrop?.displayIcon
			}
			archivedDrop?.delegate = self
			label.text = archivedDrop?.displayTitle
		}
	}

	func loadCompleted(success: Bool) {
		image.image = archivedDrop?.displayIcon
		image.isHidden = false
		label.text = archivedDrop?.displayTitle
		NSLog("load complete for drop group")
	}
}

final class ViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDropDelegate, UICollectionViewDragDelegate {

	func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		return archivedDrops[indexPath.item].dragItems
	}

	func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		let newItems = archivedDrops[indexPath.item].dragItems
		let onlyNewItems = newItems.filter { !session.items.contains($0) }
		return onlyNewItems
	}

	@IBOutlet weak var archivedItemCollectionView: UICollectionView!

	private var archivedDrops = [ArchivedDrop]()

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return archivedDrops.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ArchivedItemCell", for: indexPath) as! ArchivedItemCell
		cell.archivedDrop = archivedDrops[indexPath.item]
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {

		if let _ = coordinator.session.localDragSession {

			NSLog("local drop")

			if let destinationIndexPath = coordinator.destinationIndexPath,
				let firstDragItem = coordinator.items.first,
				let existingItem = firstDragItem.dragItem.localObject as? ArchivedDrop,
				let previousIndex = firstDragItem.sourceIndexPath {

				collectionView.performBatchUpdates({
					self.archivedDrops.remove(at: previousIndex.item)
					self.archivedDrops.insert(existingItem, at: destinationIndexPath.item)
					collectionView.moveItem(at: previousIndex, to: destinationIndexPath)
				}, completion: { finished in

				})

				coordinator.drop(firstDragItem.dragItem, toItemAt: destinationIndexPath)
			}

		} else {

			NSLog("insert drop")

			let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: archivedDrops.count, section: 0)
			if let firstDragItem = coordinator.items.first?.dragItem {

				let item = ArchivedDrop(session: coordinator.session)

				collectionView.performBatchUpdates({
					self.archivedDrops.insert(item, at: destinationIndexPath.item)
					collectionView.insertItems(at: [destinationIndexPath])
				}, completion: { finished in

				})

				coordinator.drop(firstDragItem, toItemAt: destinationIndexPath)
			}
		}
	}

	func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
		return true
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		if session.localDragSession == nil {
			return UICollectionViewDropProposal(dropOperation: .copy, intent: .insertAtDestinationIndexPath)
		} else {
			return UICollectionViewDropProposal(dropOperation: .move, intent: .insertAtDestinationIndexPath)
		}
	}

	func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
		// TODO: possibe bug
		if collectionView.numberOfItems(inSection: 0) != archivedDrops.count {
			collectionView.endInteractiveMovement()
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		archivedItemCollectionView.dataSource = self
		archivedItemCollectionView.delegate = self
		archivedItemCollectionView.dropDelegate = self
		archivedItemCollectionView.dragDelegate = self
		archivedItemCollectionView.reorderingCadence = .immediate
	}
}

