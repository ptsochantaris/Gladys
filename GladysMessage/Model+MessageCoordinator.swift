//
//  Model+MessageCoordinator.swift
//  GladysMessage
//
//  Created by Paul Tsochantaris on 07/01/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension Model {
    static var coordinator: NSFileCoordinator {
        NSFileCoordinator(filePresenter: nil)
    }

    static func prepareToSave() {}
    static func saveComplete(wasIndexOnly _: Bool) {}
    static func startupComplete() {}
}
