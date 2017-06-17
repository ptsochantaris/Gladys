//
//  ViewController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 16/06/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import MapKit

final class ArchivedDropItemType {

	let typeIdentifier: String

	private var bytes: Data?
	private var classType: ClassType?
	private let folderUrl: URL
	private let uuid = UUID()

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

	init(provider: NSItemProvider, typeIdentifier: String, parentUrl: URL) {
		self.typeIdentifier = typeIdentifier
		self.folderUrl = parentUrl.appendingPathComponent(uuid.uuidString)

		provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
			if let item = item {
				let receivedTypeString = type(of: item)
				NSLog("name: [\(provider.suggestedName ?? "")] type: [\(typeIdentifier)] class: [\(receivedTypeString)]")
			}

			if let item = item as? NSString {
				NSLog("      received string object: \(item)")
				self.setBytes(object: item, classType: .NSString)

			} else if let item = item as? NSAttributedString {
				NSLog("      received attributed string object: \(item)")
				self.setBytes(object: item, classType: .NSAttributedString)

			} else if let item = item as? UIColor {
				NSLog("      received color object: \(item)")
				self.setBytes(object: item, classType: .UIColor)

			} else if let item = item as? UIImage {
				NSLog("      received image object: \(item)")
				self.setBytes(object: item, classType: .UIImage)

			} else if let item = item as? Data {
				NSLog("      received data: \(item)")
				self.classType = .NSData
				self.bytes = item

			} else if let item = item as? MKMapItem {
				NSLog("      received map item: \(item)")
				self.setBytes(object: item, classType: .MKMapItem)

			} else if let item = item as? URL {
				if item.scheme == "file" {
					NSLog("      will duplicate item at local url: \(item)")
					provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isLocal, error in
						if let url = url {
							NSLog("      received local url: \(url)")
							let localUrl = self.copyLocal(url)
							self.setBytes(object: localUrl, classType: .NSURL)
						} else if let error = error {
							NSLog("Error fetching local url file representation: \(error.localizedDescription)")
						}
					}
				} else {
					NSLog("      received remote url: \(item)")
					self.setBytes(object: item, classType: .NSURL)
				}
			} else if let error = error {
				NSLog("      error receiving item: \(error.localizedDescription)")

			} else {
				NSLog("      unknown class")
				// TODO: generate analyitics report to record what type was received and what UTI
			}
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
}

final class ArchivedDropItem {

	let uuid = UUID()
	let suggestedName: String?
	var typeItems: [ArchivedDropItemType]!

	var myURL: URL {
		let f = FileManager.default
		let docs = f.urls(for: .documentDirectory, in: .userDomainMask).first!
		return docs.appendingPathComponent(uuid.uuidString)
	}

	init(provider: NSItemProvider) {
		suggestedName = provider.suggestedName
		typeItems = provider.registeredTypeIdentifiers.map { ArchivedDropItemType(provider: provider, typeIdentifier: $0, parentUrl: myURL) }
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

final class ArchivedDrop {

	private let uuid = UUID()
	private let createdAt = Date()
	private let items: [ArchivedDropItem]

	var displayIcon: UIImage {
		return #imageLiteral(resourceName: "iconStickyNote") // TODO: use image element from items, if available, or possibly draw from text elements
	}

	static var counter = 0

	var displayLabel: String

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

		ArchivedDrop.counter = ArchivedDrop.counter + 1
		displayLabel = "Some data \(ArchivedDrop.counter)" // TODO: enahnce with sugegsted names of elements, date, or quote text elements

		self.items = session.items.map {
			return ($0.localObject as? ArchivedDropItem)
				?? ArchivedDropItem(provider: $0.itemProvider)
		}
	}
}

final class ArchivedItemCell: UICollectionViewCell {
	@IBOutlet weak var image: UIImageView!
	@IBOutlet weak var label: UILabel!

	var archivedDrop: ArchivedDrop? {
		didSet {
			image.image = archivedDrop?.displayIcon
			label.text = archivedDrop?.displayLabel
		}
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

			let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: archivedDrops.count-1, section: 0)
			if let firstDragItem = coordinator.items.first,
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
		archivedItemCollectionView.reorderingCadence = .fast
	}
}

