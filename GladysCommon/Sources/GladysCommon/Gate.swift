import Foundation

public final actor Gate {
    private let barrier = Barrier()
    private var tickets: Int

    public init(tickets: Int) {
        self.tickets = tickets
    }

    public func takeTicket() async {
        await barrier.wait()
        tickets -= 1
        if tickets == 0 {
            await barrier.lock()
        }
    }

    public func returnTicket() async {
        tickets += 1
        await barrier.unlock()
    }
    
    nonisolated public func relaxedReturnTicket() {
        Task {
            await returnTicket()
        }
    }
}
