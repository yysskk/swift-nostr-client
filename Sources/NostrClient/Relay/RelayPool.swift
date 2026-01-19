import Foundation

/// Manages connections to multiple Nostr relays
public actor RelayPool {
    /// All relay connections
    private var relays: [URL: RelayConnection] = [:]

    /// Subscription handlers by subscription ID
    private var subscriptionHandlers: [String: @Sendable (RelayMessage) -> Void] = [:]

    public init() {}

    /// Adds a relay to the pool
    @discardableResult
    public func addRelay(url: URL) -> RelayConnection {
        if let existing = relays[url] {
            return existing
        }
        let connection = RelayConnection(url: url)
        relays[url] = connection
        return connection
    }

    /// Adds a relay to the pool by URL string
    @discardableResult
    public func addRelay(urlString: String) throws -> RelayConnection {
        guard let url = URL(string: urlString) else {
            throw NostrError.connectionFailed("Invalid URL: \(urlString)")
        }
        return addRelay(url: url)
    }

    /// Removes a relay from the pool
    public func removeRelay(url: URL) async {
        if let connection = relays[url] {
            await connection.disconnect()
            relays.removeValue(forKey: url)
        }
    }

    /// Connects to all relays in the pool
    public func connectAll() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for connection in relays.values {
                group.addTask {
                    try await connection.connect()
                }
            }
            try await group.waitForAll()
        }
    }

    /// Disconnects from all relays in the pool
    public func disconnectAll() async {
        await withTaskGroup(of: Void.self) { group in
            for connection in relays.values {
                group.addTask {
                    await connection.disconnect()
                }
            }
        }
    }

    /// Publishes an event to all connected relays
    public func publish(_ event: Event) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for connection in relays.values {
                group.addTask {
                    try await connection.publish(event)
                }
            }
            try await group.waitForAll()
        }
    }

    /// Subscribes to events on all relays
    public func subscribe(
        subscriptionId: String,
        filters: [Filter],
        handler: @escaping @Sendable (RelayMessage) -> Void
    ) async throws {
        subscriptionHandlers[subscriptionId] = handler

        try await withThrowingTaskGroup(of: Void.self) { group in
            for connection in relays.values {
                group.addTask {
                    try await connection.subscribe(subscriptionId: subscriptionId, filters: filters)
                }
            }
            try await group.waitForAll()
        }

        // Start listening for messages on all relays
        let capturedSubscriptionId = subscriptionId
        let capturedHandler = handler
        for connection in relays.values {
            Task {
                for await message in await connection.messages() {
                    if case .event(let subId, _) = message, subId == capturedSubscriptionId {
                        capturedHandler(message)
                    } else if case .endOfStoredEvents(let subId) = message, subId == capturedSubscriptionId {
                        capturedHandler(message)
                    }
                }
            }
        }
    }

    /// Unsubscribes from a subscription on all relays
    public func unsubscribe(subscriptionId: String) async throws {
        subscriptionHandlers.removeValue(forKey: subscriptionId)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for connection in relays.values {
                group.addTask {
                    try await connection.unsubscribe(subscriptionId: subscriptionId)
                }
            }
            try await group.waitForAll()
        }
    }

    /// Returns all relay connections
    public var connections: [RelayConnection] {
        Array(relays.values)
    }

    /// Returns the relay connection for a given URL
    public func relay(for url: URL) -> RelayConnection? {
        relays[url]
    }

    /// Returns the number of relays in the pool
    public var count: Int {
        relays.count
    }

    /// Returns the number of connected relays
    public func connectedCount() async -> Int {
        var count = 0
        for connection in relays.values {
            if await connection.state == .connected {
                count += 1
            }
        }
        return count
    }
}

// MARK: - Convenience Methods
public extension RelayPool {
    /// Adds multiple relays from URL strings
    func addRelays(_ urlStrings: [String]) throws {
        for urlString in urlStrings {
            _ = try addRelay(urlString: urlString)
        }
    }
}
