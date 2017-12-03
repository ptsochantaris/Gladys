//
//  MessagesViewController.swift
//  GladysMessage
//
//  Created by Paul Tsochantaris on 03/12/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import Messages

class MessagesViewController: MSMessagesAppViewController, UICollectionViewDelegate,
UICollectionViewDataSource, UISearchBarDelegate {

	@IBOutlet weak var emptyLabel: UILabel!
	@IBOutlet weak var itemsView: UICollectionView!
	@IBOutlet weak var searchBar: UISearchBar!

	private var searchTimer: PopTimer!
	private var searchVisibilityTrigger: NSLayoutConstraint!

	private func itemsPerRow(for size: CGSize) -> Int {
		if size.width < 320 {
			return min(2, Model.drops.count)
		} else if size.width < 400 {
			return min(3, Model.drops.count)
		} else if size.width < 1000 {
			return min(4, Model.drops.count)
		} else {
			return min(5, Model.drops.count)
		}
	}

	private func updateItemSize(for size: CGSize) {
		guard let f = itemsView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
		let count = CGFloat(itemsPerRow(for: size))
		var s = size
		s.width = ((s.width - ((count+1) * 10)) / count).rounded(.down)
		s.height = s.width
		f.itemSize = s
		f.invalidateLayout()
	}

	private var filteredDrops: [ArchivedDropItem] {
		if let t = searchBar.text, !t.isEmpty {
			return Model.drops.filter { $0.oneTitle.localizedCaseInsensitiveContains(t) }
		} else {
			return Model.drops
		}
	}

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return filteredDrops.count
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MessageCell", for: indexPath) as! MessageCell
		cell.dropItem = filteredDrops[indexPath.row]
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		let drop = filteredDrops[indexPath.row]
		if let a = activeConversation {
			let (text, url) = drop.textForMessage
			var finalString = text
			if let url = url {
				finalString += ": " + url.absoluteString
			}
			a.insertText(finalString) { error in
				if let error = error {
					log("Error adding text: \(error.finalDescription)")
				}
			}
			if url == nil, let previewableType = drop.typeItems.first(where:{ $0.canAttach }) {
				let previewItem = ArchivedDropItemType.PreviewItem(typeItem: previewableType)
				if let u = previewItem.previewItemURL {
					a.insertAttachment(u, withAlternateFilename: text) { error in
						if let error = error {
							log("Error adding attachment: \(error.finalDescription)")
						}
					}
				}
			}
		}
		dismiss()
	}

    override func viewDidLoad() {
        super.viewDidLoad()
		searchTimer = PopTimer(timeInterval: 0.3) { [weak self] in
			self?.searchUpdated()
		}
		itemsView.backgroundView = UIImageView(image: #imageLiteral(resourceName: "paper").resizableImage(withCapInsets: .zero, resizingMode: .tile))
		searchVisibilityTrigger = searchBar.bottomAnchor.constraint(equalTo: view.topAnchor)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
		Model.reset()
    }
    
    override func willBecomeActive(with conversation: MSConversation) {
		Model.reloadDataIfNeeded()
		itemsView.reloadData()
		emptyLabel.isHidden = Model.drops.count > 0
		searchVisibilityTrigger.isActive = presentationStyle != .expanded
    }
    
    override func didResignActive(with conversation: MSConversation) {
		Model.reset()
    }

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updateItemSize(for: view.bounds.size)
	}

	override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
		super.willTransition(to: presentationStyle)
		searchVisibilityTrigger.isActive = presentationStyle != .expanded
		UIView.animate(animations: {
			self.view.layoutIfNeeded()
		})
	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		updateItemSize(for: size)
	}

	func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
		searchTimer.push()
	}

	private func searchUpdated() {
		itemsView.reloadData()
	}
}
