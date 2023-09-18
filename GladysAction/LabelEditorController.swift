import GladysCommon
import Minions
import UIKit

final class LabelEditorController: UIViewController, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate {
    @IBOutlet private var notesText: UITextField!
    @IBOutlet private var labelText: UITextField!
    @IBOutlet private var table: UITableView!

    @IBOutlet private var headerView: UIView!
    @IBOutlet private var headerLabel: UILabel!

    private var allToggles = [String]()
    private var availableToggles = [String]()

    override func viewDidLoad() {
        super.viewDidLoad()
        itemAccessQueue.async(flags: .barrier) {
            self.allToggles = LiteModel.getLabelsWithoutLoading().sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            Task { @MainActor [weak self] in
                self?.table.isHidden = false
                self?.updateFilter(nil)
            }
        }

        notesText.text = ActionRequestViewController.noteToApply

        notifications(for: .IngestComplete) { [weak self] _ in
            self?.itemIngested()
        }

        itemIngested()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        commitNote()
    }

    private func itemIngested() {
        guard DropStore.doneIngesting else { return }

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", primaryAction: UIAction(handler: #weakSelf { _ in
            commitNote()
            sendNotification(name: .DoneSelected)
        }))
    }

    private func commitNote() {
        ActionRequestViewController.noteToApply = notesText.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func numberOfSections(in _: UITableView) -> Int {
        min(1, availableToggles.count)
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        availableToggles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelEditorCell", for: indexPath) as! LabelEditorCell

        let toggle = availableToggles[indexPath.row]
        cell.labelName.text = toggle
        cell.accessibilityLabel = toggle

        if ActionRequestViewController.labelsToApply.contains(toggle) {
            cell.tick.isHidden = false
            cell.tick.isHighlighted = true
            cell.labelName.textColor = UIColor.label
            cell.accessibilityValue = "Selected"
        } else {
            cell.tick.isHidden = true
            cell.tick.isHighlighted = false
            cell.labelName.textColor = UIColor.secondaryLabel
            cell.accessibilityValue = nil
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let toggle = availableToggles[indexPath.row]
        if let i = ActionRequestViewController.labelsToApply.firstIndex(of: toggle) {
            ActionRequestViewController.labelsToApply.remove(at: i)
        } else {
            ActionRequestViewController.labelsToApply.append(toggle)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    func tableView(_: UITableView, heightForHeaderInSection _: Int) -> CGFloat {
        40
    }

    func tableView(_: UITableView, viewForHeaderInSection _: Int) -> UIView? {
        headerView
    }

    private func updateFilter(_ text: String?) {
        let filter = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if filter.isEmpty {
            availableToggles = allToggles
        } else {
            availableToggles = allToggles.filter { $0.localizedCaseInsensitiveContains(filter) }
        }
        table.reloadData()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string != "\n" {
            if let oldText = textField.text, !oldText.isEmpty, let r = Range(range, in: oldText) {
                let newText = oldText.replacingCharacters(in: r, with: string)
                updateFilter(newText)
            } else {
                updateFilter(nil)
            }
            return true
        }

        textField.resignFirstResponder()

        guard let newTag = textField.text, !newTag.isEmpty else {
            return false
        }

        textField.text = nil
        if !allToggles.contains(newTag) {
            allToggles.append(newTag)
            allToggles.sort()
        }
        updateFilter(nil)
        if let i = allToggles.firstIndex(of: newTag) {
            let existingToggle = allToggles[i]
            let ip = IndexPath(row: i, section: 0)
            if !ActionRequestViewController.labelsToApply.contains(existingToggle) {
                tableView(table, didSelectRowAt: ip)
            }
            table.scrollToRow(at: ip, at: .middle, animated: true)
        }
        return false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if UIAccessibility.isVoiceOverRunning, labelText.isFirstResponder { // weird hack for word mode
            let left = -scrollView.adjustedContentInset.left
            if scrollView.contentOffset.x < left {
                let top = -scrollView.adjustedContentInset.top
                scrollView.contentOffset = CGPoint(x: left, y: top)
            }
        }

        headerLabel.alpha = 1.0 - min(1, max(0, scrollView.contentOffset.y / 8.0))
    }
}
