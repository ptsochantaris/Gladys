import Foundation

public final actor GateKeeper {
    private var counter: Int
    
    public init(entries: Int) {
        counter = entries
    }

    public func waitForGate() async {
        while counter < 0 {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
        }
        counter -= 1
    }

    public func signalGate() {
        counter += 1
    }
}
