//
//  LabelToggleCell.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 14/10/2017.
//  Copyright © 2017 Paul Tsochantaris. All rights reserved.
//

import UIKit

final class LabelToggleCell: UITableViewCell, UIContextMenuInteractionDelegate {
	@IBOutlet private weak var labelCount: UILabel!
	@IBOutlet private weak var labelName: UILabel!
    
    weak var parent: LabelSelector?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        let menu = UIContextMenuInteraction(delegate: self)
        addInteraction(menu)
    }
    
    var toggle: ModelFilterContext.LabelToggle? {
        didSet {
            guard let toggle = toggle else { return }
            labelName.text = toggle.name
            let c = toggle.count
            labelCount.text = c == 1 ? "1 item" : "\(c) items"
        }
    }

	override func setSelected(_ selected: Bool, animated: Bool) {
		accessoryType = selected ? .checkmark : .none
        labelName.textColor = selected ? .label : UIColor(named: "colorComponentLabel")
	}
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            
            var children = [
                UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                    if let s = self, let toggle = s.toggle {
                        s.parent?.rename(toggle: toggle)
                    }
                },
                UIAction(title: "Delete", image: UIImage(systemName: "bin.xmark"), attributes: .destructive) { _ in
                    if let s = self, let toggle = s.toggle {
                        s.parent?.delete(toggle: toggle)
                    }
                }
            ]
            
            if UIApplication.shared.supportsMultipleScenes {
                children.insert(UIAction(title: "Open in Window", image: UIImage(systemName: "uiwindow.split.2x1")) { _ in
                    if let s = self, let toggle = s.toggle {
                        s.parent?.createWindow(for: toggle)
                    }
                }, at: 1)
            }
            
            return UIMenu(title: "", image: nil, identifier: nil, options: [], children: children)
        }
    }

}
