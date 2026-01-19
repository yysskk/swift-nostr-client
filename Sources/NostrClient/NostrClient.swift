import Foundation

/// Main entry point for the Nostr client library
public actor NostrClient {
    /// The relay pool managing all connections
    public let relayPool: RelayPool

    /// The event signer (optional, required for publishing)
    private var signer: EventSigner?

    /// Subscription counter for generating unique IDs
    private var subscriptionCounter: Int = 0

    /// Active subscriptions
    private var subscriptions: [String: Subscription] = [:]

    /// Event cache for deduplication
    private var eventCache: Set<String> = []

    /// Maximum cache size
    private let maxCacheSize: Int

    public init(maxCacheSize: Int = 10000) {
        self.relayPool = RelayPool()
        self.maxCacheSize = maxCacheSize
    }

    /// Sets the signer for publishing events
    public func setSigner(_ signer: EventSigner) {
        self.signer = signer
    }

    /// Sets the signer from a private key hex string
    public func setPrivateKey(_ privateKeyHex: String) throws {
        self.signer = try EventSigner(privateKeyHex: privateKeyHex)
    }

    /// Sets the signer from an nsec
    public func setNsec(_ nsec: String) throws {
        self.signer = try EventSigner(nsec: nsec)
    }

    /// Returns the public key if a signer is set
    public var publicKey: String? {
        signer?.publicKey
    }

    /// Returns the npub if a signer is set
    public var npub: String? {
        signer?.npub
    }

    // MARK: - Relay Management

    /// Adds a relay
    @discardableResult
    public func addRelay(_ urlString: String) async throws -> RelayConnection {
        try await relayPool.addRelay(urlString: urlString)
    }

    /// Adds multiple relays
    public func addRelays(_ urlStrings: [String]) async throws {
        for urlString in urlStrings {
            _ = try await relayPool.addRelay(urlString: urlString)
        }
    }

    /// Connects to all relays
    public func connect() async throws {
        try await relayPool.connectAll()
    }

    /// Disconnects from all relays
    public func disconnect() async {
        await relayPool.disconnectAll()
    }

    // MARK: - Publishing

    /// Publishes a text note
    public func publishTextNote(content: String, tags: [[String]] = []) async throws -> Event {
        guard let signer = signer else {
            throw NostrError.signingFailed
        }

        let event = try signer.signTextNote(content: content, tags: tags)
        try await relayPool.publish(event)
        return event
    }

    /// Publishes a reply to an event
    public func publishReply(to event: Event, content: String, relayUrl: String? = nil) async throws -> Event {
        guard let signer = signer else {
            throw NostrError.signingFailed
        }

        var tags: [[String]] = []

        // Add root and reply markers (NIP-10)
        if let rootTag = event.tags.first(where: { $0.first == "e" && $0.contains("root") }) {
            tags.append(rootTag)
            var replyTag = ["e", event.id]
            if let relayUrl = relayUrl {
                replyTag.append(relayUrl)
            }
            replyTag.append("reply")
            tags.append(replyTag)
        } else {
            // This is a reply to a root event
            var rootTag = ["e", event.id]
            if let relayUrl = relayUrl {
                rootTag.append(relayUrl)
            }
            rootTag.append("root")
            tags.append(rootTag)
        }

        // Add p tag for the author we're replying to
        tags.append(["p", event.pubkey])

        let unsigned = UnsignedEvent(
            pubkey: signer.publicKey,
            kind: .textNote,
            tags: tags,
            content: content
        )

        let signedEvent = try signer.sign(unsigned)
        try await relayPool.publish(signedEvent)
        return signedEvent
    }

    /// Publishes user metadata
    public func publishMetadata(_ metadata: UserMetadata) async throws -> Event {
        guard let signer = signer else {
            throw NostrError.signingFailed
        }

        let event = try signer.signMetadata(metadata)
        try await relayPool.publish(event)
        return event
    }

    /// Publishes a reaction to an event
    public func publishReaction(to event: Event, content: String = "+") async throws -> Event {
        guard let signer = signer else {
            throw NostrError.signingFailed
        }

        let reaction = try signer.signReaction(to: event, content: content)
        try await relayPool.publish(reaction)
        return reaction
    }

    /// Publishes a repost
    public func publishRepost(of event: Event, relayUrl: String? = nil) async throws -> Event {
        guard let signer = signer else {
            throw NostrError.signingFailed
        }

        let repost = try signer.signRepost(of: event, relayUrl: relayUrl)
        try await relayPool.publish(repost)
        return repost
    }

    /// Publishes a deletion request
    public func publishDeletion(eventIds: [String], reason: String = "") async throws -> Event {
        guard let signer = signer else {
            throw NostrError.signingFailed
        }

        let deletion = try signer.signDeletion(eventIds: eventIds, reason: reason)
        try await relayPool.publish(deletion)
        return deletion
    }

    /// Publishes a raw signed event
    public func publish(_ event: Event) async throws {
        try await relayPool.publish(event)
    }

    // MARK: - Subscriptions

    /// Subscribes to events matching the given filters
    @discardableResult
    public func subscribe(
        filters: [Filter],
        handler: @escaping @Sendable (Event) -> Void
    ) async throws -> String {
        subscriptionCounter += 1
        let subscriptionId = "sub_\(subscriptionCounter)"

        let subscription = Subscription(
            id: subscriptionId,
            filters: filters,
            handler: handler
        )
        subscriptions[subscriptionId] = subscription

        let capturedSubscriptionId = subscriptionId
        try await relayPool.subscribe(subscriptionId: subscriptionId, filters: filters) { [weak self] message in
            guard let self else { return }
            Task {
                await self.handleMessage(message, subscriptionId: capturedSubscriptionId)
            }
        }

        return subscriptionId
    }

    /// Unsubscribes from a subscription
    public func unsubscribe(subscriptionId: String) async throws {
        subscriptions.removeValue(forKey: subscriptionId)
        try await relayPool.unsubscribe(subscriptionId: subscriptionId)
    }

    /// Unsubscribes from all subscriptions
    public func unsubscribeAll() async throws {
        for subscriptionId in subscriptions.keys {
            try await relayPool.unsubscribe(subscriptionId: subscriptionId)
        }
        subscriptions.removeAll()
    }

    // MARK: - Convenience Subscriptions

    /// Subscribes to a user's timeline
    @discardableResult
    public func subscribeToUserTimeline(
        pubkey: String,
        limit: Int = 100,
        handler: @escaping @Sendable (Event) -> Void
    ) async throws -> String {
        let filter = Filter.userNotes(pubkey: pubkey, limit: limit)
        return try await subscribe(filters: [filter], handler: handler)
    }

    /// Subscribes to the global feed
    @discardableResult
    public func subscribeToGlobalFeed(
        limit: Int = 100,
        handler: @escaping @Sendable (Event) -> Void
    ) async throws -> String {
        let filter = Filter.globalFeed(limit: limit)
        return try await subscribe(filters: [filter], handler: handler)
    }

    /// Subscribes to mentions of a user
    @discardableResult
    public func subscribeToMentions(
        pubkey: String,
        limit: Int = 100,
        handler: @escaping @Sendable (Event) -> Void
    ) async throws -> String {
        let filter = Filter.mentions(pubkey: pubkey, limit: limit)
        return try await subscribe(filters: [filter], handler: handler)
    }

    /// Fetches metadata for a list of pubkeys
    @discardableResult
    public func subscribeToMetadata(
        pubkeys: [String],
        handler: @escaping @Sendable (Event) -> Void
    ) async throws -> String {
        let filter = Filter.metadata(pubkeys: pubkeys)
        return try await subscribe(filters: [filter], handler: handler)
    }

    // MARK: - One-time Fetches

    /// Fetches events matching the given filters (one-time)
    public func fetch(filters: [Filter], timeout: TimeInterval = 10) async throws -> [Event] {
        let collectedEvents = EventCollector()

        let subscriptionId = try await subscribe(filters: filters) { event in
            Task {
                await collectedEvents.append(event)
            }
        }

        // Wait for EOSE or timeout
        try await Task.sleep(for: .seconds(timeout))
        try await unsubscribe(subscriptionId: subscriptionId)

        return await collectedEvents.events
    }

    /// Fetches a single event by ID
    public func fetchEvent(id: String, timeout: TimeInterval = 10) async throws -> Event? {
        let filter = Filter(ids: [id])
        let events = try await fetch(filters: [filter], timeout: timeout)
        return events.first
    }

    /// Fetches user metadata
    public func fetchMetadata(pubkey: String, timeout: TimeInterval = 10) async throws -> UserMetadata? {
        let filter = Filter.metadata(pubkeys: [pubkey])
        let events = try await fetch(filters: [filter], timeout: timeout)

        guard let event = events.first else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(UserMetadata.self, from: Data(event.content.utf8))
    }

    // MARK: - Private Methods

    private func handleMessage(_ message: RelayMessage, subscriptionId: String) {
        guard let subscription = subscriptions[subscriptionId] else { return }

        switch message {
        case .event(_, let event):
            // Deduplicate events
            guard !eventCache.contains(event.id) else { return }

            // Manage cache size
            if eventCache.count >= maxCacheSize {
                eventCache.removeAll()
            }
            eventCache.insert(event.id)

            subscription.handler(event)

        case .endOfStoredEvents:
            subscription.eoseReceived = true

        default:
            break
        }
    }
}

// MARK: - Subscription
private final class Subscription: @unchecked Sendable {
    let id: String
    let filters: [Filter]
    let handler: @Sendable (Event) -> Void
    var eoseReceived: Bool = false

    init(id: String, filters: [Filter], handler: @escaping @Sendable (Event) -> Void) {
        self.id = id
        self.filters = filters
        self.handler = handler
    }
}

// MARK: - Event Collector for thread-safe event collection
private actor EventCollector {
    var events: [Event] = []

    func append(_ event: Event) {
        events.append(event)
    }
}
