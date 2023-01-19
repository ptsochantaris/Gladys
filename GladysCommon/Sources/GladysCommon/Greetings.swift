import Foundation

public final class Greetings {
    public static let openLine = "Ready! Drop me stuff."

    public static var randomCleanLine: String {
        cleanLines[Int.random(in: 0 ..< cleanLines.count)]
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

    public static var randomGreetLine: String {
        greetLines[Int.random(in: 0 ..< greetLines.count)]
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
