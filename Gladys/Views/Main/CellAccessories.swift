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

	var squircle = false
	private var aspectLock: NSLayoutConstraint?

	override func layoutSubviews() {
		super.layoutSubviews()

		if circle {
			let smallestSide = min(bounds.size.width, bounds.size.height)
			layer.cornerRadius = (smallestSide * 0.5).rounded(.down)
			if let a = aspectLock {
				a.constant = smallestSide
			} else {
				aspectLock = widthAnchor.constraint(equalToConstant: smallestSide)
				aspectLock?.isActive = true
			}

		} else {
			layer.cornerRadius = squircle ? 5 : 0
			if let a = aspectLock {
				removeConstraint(a)
				aspectLock = nil
			}
		}
	}
}

final class ColourView: UIView {}

final class MiniMapView: UIImageView {

	private var coordinate: CLLocationCoordinate2D?
	private weak var snapshotter: MKMapSnapshotter?
	private var snapshotOptions: MKMapSnapshotter.Options?

	func show(location: MKMapItem) {

		let newCoordinate = location.placemark.coordinate
		if let coordinate = coordinate,
			newCoordinate.latitude == coordinate.latitude,
			newCoordinate.longitude == coordinate.longitude { return }

		image = nil
		snapshotOptions = nil
		coordinate = newCoordinate
		setNeedsLayout()
	}

	init(at location: MKMapItem) {
		super.init(frame: .zero)
		contentMode = .center
		show(location: location)
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		guard let coordinate = coordinate else { return }
		if bounds.isEmpty || image?.size == bounds.size { return }

		let cacheKey = NSString(format: "%f %f %f %f", coordinate.latitude, coordinate.longitude, bounds.size.width, bounds.size.height)
		if let existingImage = imageCache.object(forKey: cacheKey) {
			image = existingImage
			return
		}

		if let o = snapshotOptions, o.region.center.latitude == coordinate.latitude && o.region.center.longitude == coordinate.longitude && o.size == bounds.size {
			return
		}

		snapshotter?.cancel()
		snapshotter = nil
		alpha = 0

		let O = MKMapSnapshotter.Options()
		O.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 200.0, longitudinalMeters: 200.0)
		O.showsBuildings = true
        O.pointOfInterestFilter = .includingAll
		O.size = bounds.size
		snapshotOptions = O

		let S = MKMapSnapshotter(options: O)
		snapshotter = S

		S.start { snapshot, error in
			if let snapshot = snapshot {
				let img = snapshot.image
				imageCache.setObject(img, forKey: cacheKey)
				DispatchQueue.main.async { [weak self] in
					self?.image = img
					UIView.animate(withDuration: 0.15) {
						self?.alpha = 1
					}
				}
			}
			if let error = error {
				log("Error taking map snapshot: \(error.finalDescription)")
			}
		}
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
