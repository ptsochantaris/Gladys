//
//  MessagesViewController.swift
//  GladysMessage
//
//  Created by Paul Tsochantaris on 03/12/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit
import Messages

private var messagesCurrentOffset = CGPoint.zero
private var lastFilter: String?

class MessagesViewController: MSMessagesAppViewController, UICollectionViewDelegate,
UICollectionViewDataSource, UISearchBarDelegate {

	@IBOutlet weak var emptyLabel: UILabel!
	@IBOutlet weak var itemsView: UICollectionView!
	@IBOutlet weak var searchBar: UISearchBar!
	@IBOutlet weak var searchOffset: NSLayoutConstraint!

	private var searchTimer: PopTimer!

	private func itemsPerRow(for size: CGSize) -> Int {
		if size.width < 320 {
			return 2
		} else if size.width < 400 {
			return 3
		} else if size.width < 1000 {
			return 4
		} else {
			return 5
		}
	}

	private func updateItemSize(for size: CGSize) {
		guard size.width > 0 else { return }
		guard let f = itemsView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
		let count = CGFloat(itemsPerRow(for: size))
		var s = size
		s.width = ((s.width - ((count+1) * 10)) / count).rounded(.down)
		s.height = s.width
		f.itemSize = s
		f.sectionInset.top = searchBar.frame.size.height
		f.invalidateLayout()
	}

	private var filteredDrops: [ArchivedDropItem] {
		if let t = searchBar.text, !t.isEmpty {
			return Model.visibleDrops.filter { $0.displayTitleOrUuid.localizedCaseInsensitiveContains(t) }
		} else {
			return Model.visibleDrops
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
		guard let a = activeConversation else {
			dismiss()
			return
		}

		let drop = filteredDrops[indexPath.row]
		let (text, url) = drop.textForMessage
		var finalString = text
		if let url = url {
			finalString += " " + url.absoluteString
		}
		a.insertText(finalString) { error in
			if let error = error {
				log("Error adding text: \(error.finalDescription)")
			}
		}
		if url == nil, let attachableType = drop.attachableTypeItem {
			let link = attachableType.sharedLink
			a.insertAttachment(link, withAlternateFilename: link.lastPathComponent) { error in
				if let error = error {
					log("Error adding attachment: \(error.finalDescription)")
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
		NotificationCenter.default.addObserver(self, selector: #selector(externalDataUpdated), name: .ExternalDataUpdated, object: nil)
    }

	@objc private func externalDataUpdated() {
		emptyLabel.isHidden = Model.visibleDrops.count > 0
		updateItemSize(for: view.bounds.size)
		itemsView.reloadData()
	}

	deinit {
		log("iMessage app dismissed")
	}

	private var filePresenter: ModelFilePresenter?

	override func willBecomeActive(with conversation: MSConversation) {
		super.willBecomeActive(with: conversation)
		Model.reloadDataIfNeeded()
		if filePresenter == nil && !Model.legacyMode {
			filePresenter = ModelFilePresenter()
			NSFileCoordinator.addFilePresenter(filePresenter!)
		}
		emptyLabel.isHidden = Model.visibleDrops.count > 0
		updateItemSize(for: view.bounds.size)
		searchBar.text = lastFilter
		itemsView.reloadData()
		DispatchQueue.main.async {
			self.itemsView.contentOffset = messagesCurrentOffset
		}
	}

	override func willResignActive(with conversation: MSConversation) {
		super.willResignActive(with: conversation)
		if let m = filePresenter {
			NSFileCoordinator.removeFilePresenter(m)
			filePresenter = nil
		}
		messagesCurrentOffset = itemsView.contentOffset
		lastFilter = searchBar.text
		Model.reset()
		itemsView.reloadData()
	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		updateItemSize(for: size)
	}

	func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
		searchTimer.push()
	}

	func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
		if presentationStyle != .expanded {
			requestPresentationStyle(.expanded)
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				searchBar.becomeFirstResponder()
			}
		}
		return true
	}

	private func searchUpdated() {
		itemsView.reloadData()
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		let offset = scrollView.contentOffset.y
		if offset > -searchBar.frame.size.height {
			searchOffset.constant = min(0, -offset)
		}
	}
}
