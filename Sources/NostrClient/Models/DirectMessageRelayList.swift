import Foundation

/// NIP-17 Direct Message Relay List (kind 10050).
///
/// A replaceable event in which an author advertises the relays where they want
/// to receive private direct messages. Senders look this list up to learn where
/// to publish the gift wraps addressed to a recipient (and where to publish the
/// sender's own self-copy).
///
/// Unlike a NIP-65 relay list (``RelayListMetadata``) there is no read/write
/// distinction — every URL is a direct-message inbox — and entries are carried as
/// `relay` tags rather than `r` tags. NIP-17 recommends keeping the list short
/// (1–3 relays).
/// https://github.com/nostr-protocol/nips/blob/master/17.md
public struct DirectMessageRelayList: Codable, Hashable, Sendable {
    /// The relay URLs where the author receives direct messages, in document order.
    public let relays: [String]

    public init(relays: [String]) {
        self.relays = relays
    }

    /// Converts to the full tag array for a kind 10050 event.
    public func toTags() -> [[String]] {
        relays.map { ["relay", $0] }
    }

    /// Parses a DM relay list from a kind 10050 event. Returns nil if the event is not kind 10050.
    public init?(event: Event) {
        guard event.kind == .directMessageRelayList else {
            return nil
        }
        self.init(tags: event.tags)
    }

    /// Parses a DM relay list from raw tags (kind-agnostic). Duplicate relay URLs are removed (first wins).
    public init(tags: [[String]]) {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            guard tag.count >= 2, tag[0] == "relay", !tag[1].isEmpty else {
                continue
            }
            let url = tag[1]
            // De-duplicate on a normalized key, but keep the original URL so tags round-trip exactly.
            if seen.insert(RelayURL.normalize(url)).inserted {
                result.append(url)
            }
        }
        self.relays = result
    }
}

// MARK: - Direct Message Relay List Helpers
extension Event {
    /// Extracts the NIP-17 DM relay list from a kind 10050 event.
    /// Returns nil if the event is not a DM relay list event.
    public var directMessageRelayList: DirectMessageRelayList? {
        DirectMessageRelayList(event: self)
    }

    /// Checks if this is a kind 10050 DM relay list event.
    public var isDirectMessageRelayList: Bool {
        kind == .directMessageRelayList
    }
}
