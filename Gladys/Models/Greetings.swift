//
//  Greetings.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 07/05/2018.
//  Copyright © 2018 Paul Tsochantaris. All rights reserved.
//

import Foundation

final class Greetings {
    static let openLine = "Ready! Drop me stuff."
    
	static var randomCleanLine: String {
		let count = UInt32(cleanLines.count)
		return cleanLines[Int(arc4random_uniform(count))]
	}
	private static let cleanLines = [
		"Tidy!",
		"Woosh!",
		"Spotless!",
		"Clean desk!",
		"Neeext!",
		"Peekaboo!",
		"Cool!",
		"Zap!",
		"Nice!",
		"Feels all empty now!",
		"Very Zen!",
		"So much space!",
		"What's next?",
		"Minimalism!",
		"Done!",
		"Taken care of.",
        "Neat.",
        "Gladys zero!"
	]

	static var randomGreetLine: String {
		let count = UInt32(greetLines.count)
		return greetLines[Int(arc4random_uniform(count))]
	}
	private static let greetLines = [
		"Drop me more stuff!",
		"Hey there.",
		"Hi!",
		"Feed me!",
		"What's up?",
		"What can I keep for you?",
		"Gimme.",
		"Quiet day?",
		"How can I help?",
		"Howdy!",
		"Ready!",
		"Greetings.",
		"You called?",
		"Namaste.",
        "All set."
	]
}
