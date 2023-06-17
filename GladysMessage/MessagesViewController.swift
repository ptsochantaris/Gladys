import GladysCommon
import Messages
import UIKit

private var messagesCurrentOffset = CGPoint.zero
private var lastFilter: String?

final class MessagesViewController: MSMessagesAppViewController, UICollectionViewDelegate, UICollectionViewDataSource, UISearchBarDelegate {
    @IBOutlet private var emptyLabel: UILabel!
    @IBOutlet private var itemsView: UICollectionView!
    @IBOutlet private var searchBar: UISearchBar!
    @IBOutlet private var searchOffset: NSLayoutConstraint!

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
        s.width = ((s.width - ((count + 1) * 10)) / count).rounded(.down)
        s.height = min(175, s.width)
        f.itemSize = s
        f.sectionInset.top = searchBar.frame.size.height
        f.invalidateLayout()
    }

    private var filteredDrops: ContiguousArray<ArchivedItem> {
        if let t = searchBar.text, !t.isEmpty {
            return DropStore.visibleDrops.filter { $0.displayTitleOrUuid.localizedCaseInsensitiveContains(t) }
        } else {
            return DropStore.visibleDrops
        }
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        filteredDrops.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MessageCell", for: indexPath) as! MessageCell
        cell.dropItem = filteredDrops[indexPath.row]
        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let a = activeConversation else {
            dismiss()
            return
        }

        let drop = filteredDrops[indexPath.row]
        let (text, url) = drop.textForMessage
        var finalString = text
        if let url {
            finalString += " " + url.absoluteString
        }
        a.insertText(finalString) { error in
            if let error {
                log("Error adding text: \(error.finalDescription)")
            }
        }
        if url == nil, let attachableType = drop.attachableTypeItem {
            let link = attachableType.sharedLink
            a.insertAttachment(link, withAlternateFilename: link.lastPathComponent) { error in
                if let error {
                    log("Error adding attachment: \(error.finalDescription)")
                }
            }
        }
        dismiss()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 17.0, *) {
            searchBar.isLookToDictateEnabled = true
        }
        searchTimer = PopTimer(timeInterval: 0.3) { [weak self] in
            self?.searchUpdated()
        }
    }

    deinit {
        log("iMessage app dismissed")
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        DropStore.initialize(with: LiteModel.allItems())
        emptyLabel.isHidden = !DropStore.visibleDrops.isEmpty
        updateItemSize(for: view.bounds.size)
        searchBar.text = lastFilter
        itemsView.reloadData()
        Task { @MainActor in
            self.itemsView.contentOffset = messagesCurrentOffset
        }
    }

    override func willResignActive(with conversation: MSConversation) {
        super.willResignActive(with: conversation)
        messagesCurrentOffset = itemsView.contentOffset
        lastFilter = searchBar.text
        DropStore.reset()
        itemsView.reloadData()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        updateItemSize(for: size)
    }

    func searchBar(_: UISearchBar, textDidChange _: String) {
        searchTimer.push()
    }

    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        if presentationStyle != .expanded {
            requestPresentationStyle(.expanded)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1000 * NSEC_PER_MSEC)
                _ = searchBar.becomeFirstResponder()
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
