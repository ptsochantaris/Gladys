//
//  Network.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

class Network {

	static private var taskQueue: OperationQueue = {
		let o = OperationQueue()
		o.maxConcurrentOperationCount = 4
		return o
	}()

	static func start(with request: URLRequest, result: @escaping (Data?, URLResponse?, Error?) -> Void) {
		let g = DispatchSemaphore(value: 0)
		let task = URLSession.shared.dataTask(with: request) { data, response, error in
			result(data, response, error)
			g.signal()
		}
		taskQueue.addOperation {
			task.resume()
			g.wait()
		}
	}
	
	static func start(with url: URL, result: @escaping (Data?, URLResponse?, Error?) -> Void) {
		let g = DispatchSemaphore(value: 0)
		let task = URLSession.shared.dataTask(with: url) { data, response, error in
			result(data, response, error)
			g.signal()
		}
		taskQueue.addOperation {
			task.resume()
			g.wait()
		}
	}
}
