import Foundation

struct RelaySubscriptionMessage: Sendable {
    let relayURL: URL
    let message: RelayMessage
}
