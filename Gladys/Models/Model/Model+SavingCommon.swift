//
//  Model+SavingCommon.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 08/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

extension Model {

	static let saveQueue = DispatchQueue(label: "build.bru.gladys.saveQueue", qos: .background, attributes: [], autoreleaseFrequency: .workItem, target: nil)

	private static var needsAnotherSave = false
	private static var isSaving = false
	private static var nextSaveCallbacks: [()->Void]?

	static func queueNextSaveCallback(_ callback: @escaping ()->Void) {
		if nextSaveCallbacks == nil {
			nextSaveCallbacks = [()->Void]()
		}
		nextSaveCallbacks!.append(callback)
	}

	static func save() {
		assert(Thread.isMainThread)

		if isSaving {
			needsAnotherSave = true
		} else {
			prepareToSave()
			performSave()
		}
	}

	static var itemsEligibleForSaving: [ArchivedDropItem] {
		return drops.filter { $0.goodToSave }
	}

	private static func performSave() {

		let start = Date()

		let itemsToSave = itemsEligibleForSaving
		let uuidsToEncode = itemsToSave.compactMap { i -> UUID? in
			if i.needsSaving {
				i.needsSaving = false
				return i.uuid
			}
			return nil
		}

		isSaving = true
		needsAnotherSave = false

		saveQueue.async {

			do {
				log("\(itemsToSave.count) items to save, \(uuidsToEncode.count) items to encode")
				try self.coordinatedSave(allItems: itemsToSave, dirtyUuids: uuidsToEncode)
				log("Saved: \(-start.timeIntervalSinceNow) seconds")

			} catch {
				log("Saving Error: \(error.finalDescription)")
			}
			DispatchQueue.main.async {
				if needsAnotherSave {
					performSave()
				} else {
					isSaving = false
					if let n = nextSaveCallbacks {
						for callback in n {
							callback()
						}
						nextSaveCallbacks = nil
					}
					saveComplete()
				}
			}
		}
	}
}
