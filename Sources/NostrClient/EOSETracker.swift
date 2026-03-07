import Foundation

struct EOSETracker: Sendable {
    private(set) var expectedCount: Int?
    private(set) var receivedCount = 0

    var isComplete: Bool {
        guard let expectedCount else { return false }
        return expectedCount > 0 && receivedCount >= expectedCount
    }

    @discardableResult
    mutating func setExpectedCount(_ count: Int) -> Bool {
        expectedCount = count > 0 ? count : nil
        return isComplete
    }

    @discardableResult
    mutating func recordEOSE() -> Bool {
        receivedCount += 1
        return isComplete
    }
}
