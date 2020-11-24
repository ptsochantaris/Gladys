//
//  TouchBar.swift
//  MacGladys
//
//  Created by Paul Tsochantaris on 26/09/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

import Cocoa

extension ViewController {
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case GladysTouchBarFind.identifier:
            return GladysTouchBarFind(identifier: GladysTouchBarFind.identifier)
            
        case GladysTouchBarScrubber.identifier:
            if let s = touchBarScrubber {
                return s
            }
            touchBarScrubber = GladysTouchBarScrubber(identifier: GladysTouchBarScrubber.identifier)
            return touchBarScrubber!

        default:
            return nil
        }
    }
    
    override func makeTouchBar() -> NSTouchBar? {
        let mainBar = NSTouchBar()
        mainBar.delegate = ViewController.shared
        mainBar.defaultItemIdentifiers = [GladysTouchBarFind.identifier, GladysTouchBarScrubber.identifier]
        mainBar.customizationIdentifier = "build.bru.Gladys.touchbar"
        return mainBar
    }
}

final class GladysTouchBarFind: NSCustomTouchBarItem {
    static let identifier = NSTouchBarItem.Identifier(rawValue: "build.bru.Gladys.Touchbar.find")

    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)
        view = NSButton(image: NSImage(named: NSImage.touchBarSearchTemplateName)!, target: self, action: #selector(touchBarSearchSelected))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func touchBarSearchSelected() {
        ViewController.shared.findSelected(nil)
    }
}

final class GladysThumbnailItemView: NSScrubberItemView {
    static let identifier = NSUserInterfaceItemIdentifier(rawValue: "build.bru.Gladys.Touchbar.scrubber.view")

    private let imageView = NSImageView(frame: .zero)
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 5
        imageView.layer?.backgroundColor = NSColor(white: 0.9, alpha: 1).cgColor
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func decorate(with item: ArchivedItem) {
        imageView.image = item.displayIcon
    }
}

final class GladysTouchBarScrubber: NSCustomTouchBarItem, NSScrubberDelegate, NSScrubberDataSource, NSScrubberFlowLayoutDelegate {
    static let identifier = NSTouchBarItem.Identifier(rawValue: "build.bru.Gladys.Touchbar.scrubber")
        
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)
        
        let scrubber = NSScrubber()
        scrubber.register(GladysThumbnailItemView.self, forItemIdentifier: GladysThumbnailItemView.identifier)
        scrubber.mode = .free
        scrubber.selectionBackgroundStyle = .none
        scrubber.delegate = self
        scrubber.dataSource = self
        //scrubber.backgroundColor = .scrubberTexturedBackground
        view = scrubber
    }
    
    func reloadData() {
        (view as! NSScrubber).reloadData()
    }
    
    func numberOfItems(for scrubber: NSScrubber) -> Int {
        return Model.sharedFilter.filteredDrops.count
    }
    
    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        if let itemView = scrubber.makeItem(withIdentifier: GladysThumbnailItemView.identifier, owner: nil) as? GladysThumbnailItemView {
            let drop = Model.sharedFilter.filteredDrops[index]
            itemView.decorate(with: drop)
            return itemView
        }
        return NSScrubberItemView()
    }
    
    private static let itemSize = NSSize(width: 50, height: 30)
    func scrubber(_ scrubber: NSScrubber, layout: NSScrubberFlowLayout, sizeForItemAt itemIndex: Int) -> NSSize {
        return GladysTouchBarScrubber.itemSize
    }
    
    func scrubber(_ scrubber: NSScrubber, didSelectItemAt index: Int) {
        let drop = Model.sharedFilter.filteredDrops[index]
        ViewController.shared.touchedItem(drop)
        scrubber.selectedIndex = -1
    }
}
