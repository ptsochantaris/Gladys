//
//  HexEdit.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class HexEdit: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UIPopoverPresentationControllerDelegate {

	var bytes: Data!

	@IBOutlet var addressViewHolder: UIView!
	@IBOutlet var addressLabel: UILabel!
	@IBOutlet var addressItem: UIBarButtonItem!
	@IBOutlet weak var grid: UICollectionView!
	@IBOutlet weak var inspectorButton: UIBarButtonItem!
	@IBOutlet var asciiModeButton: UIBarButtonItem!

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return bytes.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		if asciiMode {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AsciiCell", for: indexPath) as! AsciiCell
			cell.byte = bytes[indexPath.item]
			return cell
		} else {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ByteCell", for: indexPath) as! ByteCell
			cell.byte = bytes[indexPath.item]
			return cell
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		grid.allowsMultipleSelection = true

		let selectionRecognizer = PanDirectionGestureRecognizer(direction: .horizontal, target: self, action: #selector(selectionPanned(_:)))
		grid.addGestureRecognizer(selectionRecognizer)
		navigationController?.interactivePopGestureRecognizer?.require(toFail: selectionRecognizer)

		addressLabel.text = nil
		addressItem.customView = addressViewHolder

		asciiModeButton.title = asciiMode ? "HEX" : "ASCII"
	}

	private func selectCell(at point: CGPoint) {
		guard let indexPath = grid.indexPathForItem(at: point) else { return }
		if firstSelectedIndexPath == nil {
			firstSelectedIndexPath = indexPath
		}

		let firstItem = min(indexPath.item, firstSelectedIndexPath!.item)
		let lastItem = max(indexPath.item, firstSelectedIndexPath!.item)

		for ip in grid.indexPathsForSelectedItems ?? [] {
			grid.deselectItem(at: ip, animated: false)
		}

		for item in firstItem ... lastItem {
			grid.selectItem(at: IndexPath(item: item, section: 0), animated: false, scrollPosition: .centeredHorizontally)
		}
		inspectorButton.isEnabled = true
		if let i = inspector {
			i.bytes = selectedBytes
		}

		let start = String(firstItem, radix: 16, uppercase: true)
		let end = String(lastItem, radix: 16, uppercase: true)
		if start == end {
			addressLabel.text = "#\(start)"
		} else {
			addressLabel.text = "#\(start) - #\(end)"
		}
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		if let point = collectionView.cellForItem(at: indexPath)?.frame.origin {
			clearSelection()
			selectCell(at: point)
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
		addressLabel.text = nil
	}

	private var firstSelectedIndexPath: IndexPath?

	@objc private func selectionPanned(_ recognizer: PanDirectionGestureRecognizer) {
		switch recognizer.state {
		case .began:
			clearSelection()
			let l = recognizer.location(in: grid)
			selectCell(at: l)
		case .changed:
			selectCell(at: recognizer.location(in: grid))
		default:
			break
		}
	}

	@IBAction func inspectSelected(_ sender: UIBarButtonItem) {
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

	@IBOutlet weak var ascii: UIBarButtonItem!

	@IBAction func asciiSelected(_ sender: UIBarButtonItem) {
		let selectedIndexes = grid.indexPathsForSelectedItems
		asciiMode = !asciiMode
		sender.title = asciiMode ? "HEX" : "ASCII"
		grid.reloadData()
		for i in selectedIndexes ?? [] {
			grid.selectItem(at: i, animated: false, scrollPosition: .centeredHorizontally)
		}
	}

	///////////////////////////////////

	private var lastSize = CGSize.zero

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if lastSize != view.frame.size {
			lastSize = view.frame.size
			grid.collectionViewLayout.invalidateLayout()
			grid.reloadData()
		}
	}
}
