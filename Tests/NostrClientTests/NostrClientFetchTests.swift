import Foundation
import Testing
@testable import NostrClient

@Suite("NostrClient Fetch Tests")
struct NostrClientFetchTests {

    @Test("EOSE tracker waits for every expected relay")
    func eoseTrackerWaitsForEveryExpectedRelay() {
        var tracker = EOSETracker()

        #expect(tracker.setExpectedCount(2) == false)
        #expect(tracker.recordEOSE() == false)
        #expect(tracker.isComplete == false)
        #expect(tracker.recordEOSE() == true)
        #expect(tracker.isComplete == true)
    }

    @Test("EOSE tracker handles early EOSE before relay count is known")
    func eoseTrackerHandlesEarlyEOSE() {
        var tracker = EOSETracker()

        #expect(tracker.recordEOSE() == false)
        #expect(tracker.isComplete == false)
        #expect(tracker.setExpectedCount(1) == true)
        #expect(tracker.isComplete == true)
    }

    @Test("Fetch propagates task cancellation")
    func fetchPropagatesTaskCancellation() async throws {
        let client = NostrClient()

        let fetchTask = Task {
            try await client.fetch(filters: [Filter()], timeout: 10)
        }

        try await Task.sleep(for: .milliseconds(100))
        fetchTask.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await fetchTask.value
        }
    }
}
