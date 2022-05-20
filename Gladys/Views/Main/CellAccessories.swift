//
//  CellAccessories.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 18/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation

final class GladysImageView: UIImageView {

	var circle: Bool = false {
		didSet {
			if oldValue != circle {
				setNeedsLayout()
			}
		}
	}

	private var aspectLock: NSLayoutConstraint?
    var wideMode = false

	override func layoutSubviews() {
		super.layoutSubviews()

		if circle {
			let smallestSide = min(bounds.size.width, bounds.size.height)
            layer.cornerRadius = (smallestSide * 0.5).rounded(.down)
            layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMinXMinYCorner]

			if let a = aspectLock {
				a.constant = smallestSide
			} else {
				aspectLock = widthAnchor.constraint(equalToConstant: smallestSide)
				aspectLock?.isActive = true
			}

        } else if wideMode {
            layer.cornerRadius = 10
            layer.maskedCorners = [.layerMinXMaxYCorner, .layerMinXMinYCorner]
            if let a = aspectLock {
                removeConstraint(a)
                aspectLock = nil
            }

		} else {
            layer.cornerRadius = 5
            layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMinXMinYCorner]
            if let a = aspectLock {
                removeConstraint(a)
                aspectLock = nil
            }
		}
	}
}

final class ColourView: UIView {}

final class MiniMapView: UIImageView {

    private var snapshotOptions = Images.SnapshotOptions(coordinate: kCLLocationCoordinate2DInvalid, range: 200, outputSize: CGSize(width: 512, height: 512))

	func show(location: MKMapItem) {

		let newCoordinate = location.placemark.coordinate
        if snapshotOptions.coordinate == newCoordinate { return }
        snapshotOptions.coordinate = newCoordinate
        
        let cacheKey = "\(newCoordinate.latitude) \(newCoordinate.longitude)"
        if let existingImage = imageCache[cacheKey] {
            image = existingImage
            return
        }

        image = nil

        Task {
            if let img = try? await Images.shared.mapSnapshot(with: snapshotOptions) {
                imageCache[cacheKey] = img
                image = img
            }
        }
	}

	init(at location: MKMapItem) {
		super.init(frame: .zero)
		contentMode = .center
		show(location: location)
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
