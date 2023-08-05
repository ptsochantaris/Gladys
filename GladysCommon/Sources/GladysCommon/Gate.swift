import AsyncAlgorithms

public struct Gate {
    private let queue = AsyncChannel<Void>()

    public init(tickets: Int) {
        for _ in 0 ..< tickets {
            returnTicket()
        }
    }

    public func takeTicket() async {
        for await _ in queue {
            return
        }
    }

    public func returnTicket() {
        Task {
            await queue.send(())
        }
    }
}
