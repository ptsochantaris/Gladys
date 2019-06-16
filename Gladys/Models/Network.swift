//
//  Network.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

final class Network {

	static private var taskQueue: OperationQueue = {
		let o = OperationQueue()
		o.maxConcurrentOperationCount = 8
		return o
	}()

	static func fetch(_ url: URL, method: String? = nil, result: @escaping (Data?, URLResponse?, Error?) -> Void) {
		let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
		var request = URLRequest(url: url)
		if let method = method {
			request.httpMethod = method
		}
		request.setValue("Gladys/\(v) (iOS; iOS)", forHTTPHeaderField: "User-Agent")

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
