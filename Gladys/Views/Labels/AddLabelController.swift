import UIKit

protocol AddLabelControllerDelegate: AnyObject {
    func addLabelController(_ addLabelController: AddLabelController, didEnterLabel: String?)
}

final class AddLabelController: GladysViewController, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate {
    @IBOutlet private var labelText: UITextField!
    @IBOutlet private var table: UITableView!

    var label: String?
    var exclude = Set<String>()

    weak var delegate: AddLabelControllerDelegate?

    private var sections = [Filter.Toggle.Section]()

    private var dirty = false

    private var filter = "" {
        didSet {
            update()
            table.reloadData()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        labelText.text = label
        update()

        if #available(iOS 15.0, *) {
            table.allowsFocus = true
            table.remembersLastFocusedIndexPath = true
            table.focusGroupIdentifier = "build.bru.gladys.tablefocus"
            labelText.focusGroupIdentifier = "build.bru.gladys.labelfocus"
        }
    }

    var modelFilter: Filter!

    private func update() {
        sections.removeAll()

        if filter.isEmpty {
            let recent = Filter.Toggle.Section.latestLabels.filter { !exclude.contains($0) && !$0.isEmpty }.prefix(3)
            if !recent.isEmpty {
                sections.append(Filter.Toggle.Section.filtered(labels: Array(recent), title: "Recent"))
            }
            let s = modelFilter.labelToggles.compactMap { toggle -> String? in
                if case let .userLabel(text) = toggle.function {
                    return text
                }
                return nil
            }
            sections.append(Filter.Toggle.Section.filtered(labels: s, title: "All Labels"))
        } else {
            let s = modelFilter.labelToggles.compactMap { toggle -> String? in
                if case let .userLabel(text) = toggle.function {
                    return text.localizedCaseInsensitiveContains(filter) ? text : nil
                }
                return nil
            }
            sections.append(Filter.Toggle.Section.filtered(labels: s, title: "Suggested Labels"))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)

        let h: CGFloat = modelFilter.labelToggles.isEmpty ? 67 : 320
        preferredContentSize = CGSize(width: preferredContentSize.width, height: h)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        labelText.becomeFirstResponder()
    }

    func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].labels.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelListCell") as! LabelListCell
        cell.labelName.text = sections[indexPath.section].labels[indexPath.row]
        return cell
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        let l = sections[indexPath.section].labels[indexPath.row]
        labelText.text = l
        dirty = true
        dismiss(animated: true)
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string == "\n" {
            dismiss(animated: true)
            return false
        } else {
            dirty = true
            if let t = textField.text, let r = Range(range, in: t) {
                filter = t.replacingCharacters(in: r, with: string)
            }
            return true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let result = dirty ? labelText.text?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if let result, !result.isEmpty {
            var latest = Filter.Toggle.Section.latestLabels
            if let i = latest.firstIndex(of: result) {
                latest.remove(at: i)
            }
            latest.insert(result, at: 0)
            Filter.Toggle.Section.latestLabels = Array(latest.prefix(10))
        }
        dirty = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            delegate?.addLabelController(self, didEnterLabel: result)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if UIAccessibility.isVoiceOverRunning, labelText.isFirstResponder { // weird hack for word mode
            let left = -scrollView.adjustedContentInset.left
            if scrollView.contentOffset.x < left {
                let top = -scrollView.adjustedContentInset.top
                scrollView.contentOffset = CGPoint(x: left, y: top)
            }
        }
    }
}
