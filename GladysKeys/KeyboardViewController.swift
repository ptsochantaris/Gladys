//
//  KeyboardViewController.swift
//  GladysKeys
//
//  Created by Paul Tsochantaris on 08/08/2020.
//  Copyright © 2020 Paul Tsochantaris. All rights reserved.
//

import UIKit

private var latestOffset = CGPoint.zero

final class KeyboardViewController: UIInputViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDragDelegate {

    @IBOutlet private weak var emptyLabel: UILabel!
    @IBOutlet private weak var itemsView: UICollectionView!
    @IBOutlet private weak var nextKeyboardButton: UIButton!
    @IBOutlet private weak var dismissButton: UIButton!
    @IBOutlet private weak var spaceButton: UIButton!
    @IBOutlet private weak var backspaceButton: UIButton!
    @IBOutlet private weak var enterButton: UIButton!
        
    private func itemsPerRow(for size: CGSize) -> Int {
        if size.width <= 414 {
            return 3
        } else if size.width <= 768 {
            return 5
        } else {
            return 6
        }
    }

    private func updateItemSize(for size: CGSize) {
        guard size.width > 0 else { return }
        guard let layout = itemsView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let columnCount = CGFloat(itemsPerRow(for: size))
        
        let extras = layout.minimumInteritemSpacing * (columnCount - 1) + layout.sectionInset.left + layout.sectionInset.right
        let side = ((size.width - extras) / columnCount).rounded(.down)
        
        layout.itemSize = CGSize(width: side, height: side)
        layout.invalidateLayout()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return Model.visibleDrops.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MessageCell", for: indexPath) as! MessageCell
        cell.dropItem = Model.visibleDrops[indexPath.row]
        return cell
    }

    @IBAction private func closeTapped(_ sender: UIButton) {
        dismissKeyboard()
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let drop = Model.visibleDrops[indexPath.row]
        let (text, url) = drop.textForMessage
        textDocumentProxy.insertText(url?.absoluteString ?? text)
    }
    
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let drop = Model.visibleDrops[indexPath.item]
        return [drop.dragItem]
    }

    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        let item = Model.visibleDrops[indexPath.item].dragItem
        if !session.items.contains(item) {
            return [item]
        } else {
            return []
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
        dragCompletionGroup.enter()
    }
    
    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        dragCompletionGroup.leave()
    }
    
    func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        if let cell = itemsView.cellForItem(at: indexPath) as? MessageCell, let b = cell.backgroundView {
            let corner = b.layer.cornerRadius
            let path = UIBezierPath(roundedRect: b.frame, byRoundingCorners: .allCorners, cornerRadii: CGSize(width: corner, height: corner))
            let params = UIDragPreviewParameters()
            params.visiblePath = path
            return params
        } else {
            return nil
        }
    }

    @IBAction private func returnSelected(_ sender: UIButton) {
        textDocumentProxy.insertText("\n")
    }
    
    @IBAction private func spaceSelected(_ sender: UIButton) {
        textDocumentProxy.insertText(" ")
    }
    
    @IBAction private func deleteSelected(_ sender: UIButton) {
        textDocumentProxy.deleteBackward()
    }

    @objc private func externalDataUpdated() {
        emptyLabel.isHidden = !Model.visibleDrops.isEmpty
        updateItemSize(for: view.bounds.size)
        itemsView.reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        log("Keyboard extension dismissed")
    }

    private var filePresenter: ModelFilePresenter?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Model.reloadDataIfNeeded()
        if filePresenter == nil {
            filePresenter = ModelFilePresenter()
            NSFileCoordinator.addFilePresenter(filePresenter!)
        }
        emptyLabel.isHidden = !Model.visibleDrops.isEmpty
        updateItemSize(for: view.bounds.size)
        itemsView.reloadData()
        view.layoutIfNeeded()
        itemsView.contentOffset = latestOffset
    }
    
    private let dragCompletionGroup = DispatchGroup()
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dragCompletionGroup.notify(queue: .main) {
            latestOffset = self.itemsView.contentOffset
            if let m = self.filePresenter {
                NSFileCoordinator.removeFilePresenter(m)
                self.filePresenter = nil
            }
            Model.reset()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.updateItemSize(for: size)
        coordinator.animate(alongsideTransition: { _ in
            self.view.layoutIfNeeded()
        }, completion: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dismissButton.isHidden = UIDevice.current.userInterfaceIdiom != .pad
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        NotificationCenter.default.addObserver(self, selector: #selector(externalDataUpdated), name: .ModelDataUpdated, object: nil)
        itemsView.dragDelegate = self
        itemsView.dragInteractionEnabled = UIDevice.current.userInterfaceIdiom == .pad
        
        for b in [dismissButton, spaceButton, backspaceButton, enterButton, nextKeyboardButton] {
            b?.layer.masksToBounds = true
            b?.layer.cornerRadius = 5
        }
        
        dismissButton.backgroundColor = UIColor(named: "colorKeyboardGray")
        spaceButton.backgroundColor = UIColor(named: "colorKeyboardBright")
        backspaceButton.backgroundColor = UIColor(named: "colorKeyboardGray")
        nextKeyboardButton.backgroundColor = UIColor(named: "colorKeyboardGray")
    }

    override func viewWillLayoutSubviews() {
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }
}
