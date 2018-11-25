//
//  HexEdit.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class HexEdit: GladysViewController, UICollectionViewDataSource, UICollectionViewDelegate, UIPopoverPresentationControllerDelegate {

	var bytes: Data!

	@IBOutlet private weak var addressViewHolder: UIView!
	@IBOutlet private weak var addressButton: UIButton!
	@IBOutlet private weak var addressItem: UIBarButtonItem!
	@IBOutlet private weak var grid: UICollectionView!
	@IBOutlet private weak var inspectorButton: UIBarButtonItem!
	@IBOutlet private weak var asciiModeButton: UIBarButtonItem!

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return bytes.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		if asciiMode {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AsciiCell", for: indexPath) as! AsciiCell
			cell.byte = bytes[indexPath.item]
			cell.address = Int64(indexPath.item)
			return cell
		} else {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ByteCell", for: indexPath) as! ByteCell
			cell.byte = bytes[indexPath.item]
			cell.address = Int64(indexPath.item)
			return cell
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setToolbarHidden(false, animated: animated)
	}

	override func darkModeChanged() {
		super.darkModeChanged()
		addressButton.tintColor = ViewController.tintColor
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		doneLocation = .right
		grid.allowsMultipleSelection = true

		inspectorButton.accessibilityLabel = "Inspect selection"
		addressItem.accessibilityLabel = "Selected addresses"

		grid.backgroundView = UIImageView(image: (ViewController.shared.itemView.backgroundView as! UIImageView).image)
		grid.accessibilityTraits = grid.accessibilityTraits.union(.allowsDirectInteraction)
		grid.accessibilityLabel = "Data grid"

		let selectionRecognizer = PanDirectionGestureRecognizer(direction: .horizontal, target: self, action: #selector(selectionPanned(_:)))
		grid.addGestureRecognizer(selectionRecognizer)
		navigationController?.interactivePopGestureRecognizer?.require(toFail: selectionRecognizer)

		addressItem.customView = addressViewHolder
		asciiModeButton.title = asciiMode ? "HEX" : "ASCII"
		clearSelection()

		if bytes.count == 0 {
			addressButton.isEnabled = false
			ascii.isEnabled = false
		}
	}

	private func selectCell(at point: CGPoint, animated: Bool) {

		guard let indexPath = grid.indexPathForItem(at: point) else {
			return
		}

		if firstSelectedIndexPath == nil {
			firstSelectedIndexPath = indexPath
		}

		let firstItem = min(indexPath.item, firstSelectedIndexPath!.item)
		let lastItem = max(indexPath.item, firstSelectedIndexPath!.item)

		let selectedPaths = grid.indexPathsForSelectedItems?.sorted() ?? []
		if selectedPaths.first?.item == firstItem && selectedPaths.last?.item == lastItem {
			return
		}

		for ip in selectedPaths {
			grid.deselectItem(at: ip, animated: false)
		}

		for item in firstItem ... lastItem {
			grid.selectItem(at: IndexPath(item: item, section: 0), animated: false, scrollPosition: .centeredHorizontally)
		}
		inspectorButton.isEnabled = true
		if let i = inspector {
			i.bytes = selectedBytes
		}

		if !animated {
			UIView.setAnimationsEnabled(false)
		}
		let start = String(firstItem, radix: 16, uppercase: true)
		let end = String(lastItem, radix: 16, uppercase: true)
		if start == end {
			addressButton.setTitle("0x\(start)", for: .normal)
			addressButton.accessibilityLabel = "Location \(start)"
		} else {
			let newTitle = "0x\(start) - 0x\(end)"
			addressButton.setTitle(newTitle, for: .normal)
			addressButton.accessibilityLabel = "Locations \(start) until \(end)"
			UIAccessibility.post(notification: .announcement, argument: addressButton.accessibilityLabel)
		}
		if !animated {
			addressButton.layoutIfNeeded()
			UIView.setAnimationsEnabled(true)
		}
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		if let point = collectionView.cellForItem(at: indexPath)?.frame.origin {
			clearSelection()
			selectCell(at: point, animated: true)
		}
	}

	func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
		clearSelection()
		if let i = inspector {
			i.bytes = selectedBytes
		}
	}

	private func clearSelection() {
		firstSelectedIndexPath = nil
		for ip in grid.indexPathsForSelectedItems ?? [] {
			grid.deselectItem(at: ip, animated: false)
		}
		inspectorButton.isEnabled = false
		addressButton.setTitle("Jump To Address", for: .normal)
	}

	private var firstSelectedIndexPath: IndexPath?

	@objc private func selectionPanned(_ recognizer: PanDirectionGestureRecognizer) {
		switch recognizer.state {
		case .began:
			clearSelection()
			let l = recognizer.location(in: grid)
			selectCell(at: l, animated: true)
		case .changed:
			selectCell(at: recognizer.location(in: grid), animated: false)
		default:
			break
		}
	}

	@IBAction private func inspectSelected(_ sender: UIBarButtonItem) {
		performSegue(withIdentifier: "inspector", sender: nil)
	}

	var selectedBytes: [UInt8] {
		return grid.indexPathsForSelectedItems?.sorted { $0.item < $1.item }.map { bytes[$0.item] } ?? []
	}

	private var inspector: DataInspector?

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "inspector", let i = segue.destination as? DataInspector {
			i.bytes = selectedBytes
			i.popoverPresentationController?.passthroughViews = [grid]
			i.popoverPresentationController?.backgroundColor = .white
			i.popoverPresentationController?.delegate = self
			inspector = i
		}
	}

	func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
		inspector = nil
		return true
	}

	func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
		return .none
	}

	private var asciiMode: Bool {
		get {
			return DataInspector.getBool("Hex-asciiMode")
		}
		set {
			DataInspector.setBool("Hex-asciiMode", newValue)
		}
	}

	@IBOutlet private weak var ascii: UIBarButtonItem!

	@IBAction private func asciiSelected(_ sender: UIBarButtonItem) {
		let selectedIndexes = grid.indexPathsForSelectedItems
		asciiMode = !asciiMode
		sender.title = asciiMode ? "HEX" : "ASCII"
		grid.reloadData()
		for i in selectedIndexes ?? [] {
			grid.selectItem(at: i, animated: false, scrollPosition: .centeredHorizontally)
		}
	}

	@IBAction private func addressSelected(_ sender: Any) {
		let a = UIAlertController(title: "Jump To Address", message: nil, preferredStyle: .alert)
		a.addTextField { field in
			let ip = self.grid.indexPathsForSelectedItems ?? self.grid.indexPathsForVisibleItems
			if let f = ip.first {
				field.text = String(f.item, radix: 16, uppercase: true)
			}
		}
		a.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
			if let address = Int(a.textFields?.first?.text ?? "", radix: 16) {
				let finalAddress = min(address, self.bytes.count-1)
				let newIP = IndexPath(item: finalAddress, section: 0)
				self.clearSelection()
				self.grid.selectItem(at: newIP, animated: false, scrollPosition: .centeredVertically)
				let hexFinal = String(finalAddress, radix: 16, uppercase: true)
				self.addressButton.setTitle("0x\(hexFinal)", for: .normal)
			}
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
	}

	///////////////////////////////////

	private var lastSize = CGSize.zero

	override var preferredContentSize: CGSize {
		didSet {
			navigationController?.preferredContentSize = preferredContentSize
		}
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if lastSize != view.frame.size && !view.frame.isEmpty {
			lastSize = view.frame.size
			let H = max(grid.collectionViewLayout.collectionViewContentSize.height, 120)
			preferredContentSize = CGSize(width: preferredContentSize.width, height: H)
			grid.collectionViewLayout.invalidateLayout()
		}
	}
}
