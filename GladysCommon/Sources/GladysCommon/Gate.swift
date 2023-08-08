import Lista

public final actor Gate {
    private var headroom: Int
    private let queue = Lista<() -> Void>()

    public init(tickets: Int) {
        headroom = tickets
    }

    public func takeTicket() async {
        guard headroom == 0 else {
            headroom -= 1
            return
        }
        
        await withCheckedContinuation { continuation in
            queue.append {
                continuation.resume()
            }
        }
    }

    private func _returnTicket() {
        if let nextInQueue = queue.pop() {
            nextInQueue()
        } else {
            headroom += 1
        }
    }

    nonisolated public func returnTicket() {
        Task.detached {
            await self._returnTicket()
        }
    }
}
