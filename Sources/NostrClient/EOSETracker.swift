import Foundation

struct EOSETracker: Sendable {
    private(set) var expectedRelays: Set<URL>?
    private(set) var receivedRelays: Set<URL> = []

    var isComplete: Bool {
        guard let expectedRelays else { return false }
        return !expectedRelays.isEmpty && expectedRelays.isSubset(of: receivedRelays)
    }

    @discardableResult
    mutating func setExpectedRelays(_ relays: Set<URL>) -> Bool {
        expectedRelays = relays.isEmpty ? nil : relays
        return isComplete
    }

    @discardableResult
    mutating func recordEOSE(from relayURL: URL) -> Bool {
        receivedRelays.insert(relayURL)
        return isComplete
    }
}
