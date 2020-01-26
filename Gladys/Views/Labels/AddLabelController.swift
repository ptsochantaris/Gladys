//
//  AddLabelController.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 15/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

protocol AddLabelControllerDelegate: class {
	func addLabelController(_ addLabelController: AddLabelController, didEnterLabel: String?)
}

final class AddLabelController: GladysViewController, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate {

	@IBOutlet private weak var labelText: UITextField!
	@IBOutlet private weak var table: UITableView!

	var label: String?
    var exclude = Set<String>()

	weak var delegate: AddLabelControllerDelegate?
        
    private var sections = [ModelFilterContext.LabelToggle.Section]()

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
	}
    
    var modelFilter: ModelFilterContext!

    private func update() {
        
        sections.removeAll()
        
        if filter.isEmpty {
            let recent = ModelFilterContext.LabelToggle.Section.latestLabels.filter { !exclude.contains($0) && !$0.isEmpty }.prefix(3)
            if !recent.isEmpty {
                sections.append(ModelFilterContext.LabelToggle.Section.filtered(labels: Array(recent), title: "Recent Labels"))
            }
            let s = modelFilter.labelToggles.compactMap { $0.emptyChecker ? nil : $0.name }
            sections.append(ModelFilterContext.LabelToggle.Section.filtered(labels: s, title: "All Labels"))
        } else {
            let s = modelFilter.labelToggles.compactMap { $0.name.localizedCaseInsensitiveContains(filter) && !$0.emptyChecker ? $0.name : nil }
            sections.append(ModelFilterContext.LabelToggle.Section.filtered(labels: s, title: "Suggested Labels"))
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

	func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].labels.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "LabelListCell") as! LabelListCell
        cell.labelName.text = sections[indexPath.section].labels[indexPath.row]
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let l = sections[indexPath.section].labels[indexPath.row]
        labelText.text = l
        dirty = true
        dismiss(animated: true, completion: nil)
	}
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }
        
	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			dismiss(animated: true, completion: nil)
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
        if let result = result, !result.isEmpty {
            var latest = ModelFilterContext.LabelToggle.Section.latestLabels
            if let i = latest.firstIndex(of: result) {
                latest.remove(at: i)
            }
            latest.insert(result, at: 0)
            ModelFilterContext.LabelToggle.Section.latestLabels = Array(latest.prefix(10))
        }
		dirty = false
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			self.delegate?.addLabelController(self, didEnterLabel: result)
		}
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		if UIAccessibility.isVoiceOverRunning && labelText.isFirstResponder { // weird hack for word mode
			let left = -scrollView.adjustedContentInset.left
			if scrollView.contentOffset.x < left {
				let top = -scrollView.adjustedContentInset.top
				scrollView.contentOffset = CGPoint(x: left, y: top)
			}
		}
	}    
}
