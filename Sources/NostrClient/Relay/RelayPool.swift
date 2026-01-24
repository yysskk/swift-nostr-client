import Foundation

/// Manages connections to multiple Nostr relays
public actor RelayPool {
    /// All relay connections
    private var relays: [URL: RelayConnection] = [:]

    /// Subscription handlers by subscription ID
    private var subscriptionHandlers: [String: @Sendable (RelayMessage) -> Void] = [:]

    /// Subscription filters by subscription ID (for resubscription after reconnect)
    private var subscriptionFilters: [String: [Filter]] = [:]

    /// Pool configuration
    public let config: RelayPoolConfig

    /// Event deduplication cache with timestamps
    private var eventCache: [String: Date] = [:]

    /// Last cache cleanup time
    private var lastCacheCleanup: Date = Date()

    public init(config: RelayPoolConfig = .default) {
        self.config = config
    }

    /// Adds a relay to the pool
    @discardableResult
    public func addRelay(url: URL, config: RelayConnectionConfig? = nil) -> RelayConnection {
        if let existing = relays[url] {
            return existing
        }
        let connection = RelayConnection(url: url, config: config ?? self.config.defaultRelayConfig)
        relays[url] = connection
        setupReconnectionMonitoring(for: connection)
        return connection
    }

    /// Adds a relay to the pool by URL string
    @discardableResult
    public func addRelay(urlString: String, config: RelayConnectionConfig? = nil) throws -> RelayConnection {
        guard let url = URL(string: urlString) else {
            throw NostrError.connectionFailed("Invalid URL: \(urlString)")
        }
        return addRelay(url: url, config: config)
    }

    /// Sets up monitoring for relay reconnection to resubscribe
    private func setupReconnectionMonitoring(for connection: RelayConnection) {
        Task {
            var wasConnected = false
            for await state in await connection.stateChanges() {
                switch state {
                case .connected:
                    if wasConnected {
                        // This is a reconnection, resubscribe to all active subscriptions
                        await resubscribeOnReconnect(connection: connection)
                    }
                    wasConnected = true
                case .disconnected, .failed:
                    wasConnected = false
                default:
                    break
                }
            }
        }
    }

    /// Resubscribes to all active subscriptions on a reconnected relay
    private func resubscribeOnReconnect(connection: RelayConnection) async {
        for (subscriptionId, filters) in subscriptionFilters {
            do {
                try await connection.subscribe(subscriptionId: subscriptionId, filters: filters)
            } catch {
                // Log error but continue with other subscriptions
            }
        }
    }

    /// Removes a relay from the pool
    public func removeRelay(url: URL) async {
        if let connection = relays[url] {
            await connection.disconnect()
            relays.removeValue(forKey: url)
        }
    }

    /// Connects to all relays in the pool.
    /// Tolerates partial failures - succeeds if at least one relay connects.
    /// - Returns: The number of successfully connected relays
    /// - Throws: Only if all relays fail to connect
    @discardableResult
    public func connectAll() async throws -> Int {
        var successCount = 0

        await withTaskGroup(of: Bool.self) { group in
            for connection in relays.values {
                group.addTask {
                    do {
                        try await connection.connect()
                        return true
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                if success {
                    successCount += 1
                }
            }
        }

        if successCount == 0 && !relays.isEmpty {
            throw NostrError.connectionFailed("All relays failed to connect")
        }

        return successCount
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
    /// Succeeds if at least one relay accepts the event
    public func publish(_ event: Event) async throws {
        var successCount = 0
        var lastError: Error?

        await withTaskGroup(of: Result<Void, Error>.self) { group in
            for connection in relays.values {
                group.addTask {
                    do {
                        try await connection.publish(event)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for await result in group {
                switch result {
                case .success:
                    successCount += 1
                case .failure(let error):
                    lastError = error
                }
            }
        }

        // Succeed if at least one relay accepted the event
        if successCount == 0, let error = lastError {
            throw error
        }
    }

    /// Subscribes to events on all relays.
    /// Tolerates partial failures - succeeds if at least one relay accepts the subscription.
    /// Events are deduplicated across relays.
    /// - Returns: The number of relays that successfully subscribed
    /// - Throws: Only if all relays fail to subscribe
    @discardableResult
    public func subscribe(
        subscriptionId: String,
        filters: [Filter],
        handler: @escaping @Sendable (RelayMessage) -> Void
    ) async throws -> Int {
        subscriptionHandlers[subscriptionId] = handler
        subscriptionFilters[subscriptionId] = filters

        // Start listening for messages BEFORE sending subscription request
        // This ensures we don't miss any events that arrive immediately after subscribing
        let capturedSubscriptionId = subscriptionId
        for connection in relays.values {
            Task { [weak self] in
                for await message in await connection.messages() {
                    guard let self else { return }
                    switch message {
                    case .event(let subId, let event) where subId == capturedSubscriptionId:
                        // Deduplicate events across relays
                        let isDuplicate = await self.isDuplicateEvent(eventId: event.id)
                        if !isDuplicate {
                            await self.markEventAsSeen(eventId: event.id)
                            if let currentHandler = await self.subscriptionHandlers[capturedSubscriptionId] {
                                currentHandler(message)
                            }
                        }
                    case .endOfStoredEvents(let subId) where subId == capturedSubscriptionId:
                        if let currentHandler = await self.subscriptionHandlers[capturedSubscriptionId] {
                            currentHandler(message)
                        }
                    default:
                        break
                    }
                }
            }
        }

        // Small delay to ensure message streams are set up
        try await Task.sleep(for: .milliseconds(10))

        // Now send subscription requests to all relays, tolerating failures
        var successCount = 0

        await withTaskGroup(of: Bool.self) { group in
            for connection in relays.values {
                group.addTask {
                    do {
                        try await connection.subscribe(subscriptionId: subscriptionId, filters: filters)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                if success {
                    successCount += 1
                }
            }
        }

        if successCount == 0 && !relays.isEmpty {
            throw NostrError.relayError("Failed to subscribe on any relay")
        }

        return successCount
    }

    /// Unsubscribes from a subscription on all relays.
    /// Tolerates partial failures - best effort unsubscription.
    public func unsubscribe(subscriptionId: String) async {
        subscriptionHandlers.removeValue(forKey: subscriptionId)
        subscriptionFilters.removeValue(forKey: subscriptionId)

        await withTaskGroup(of: Void.self) { group in
            for connection in relays.values {
                group.addTask {
                    try? await connection.unsubscribe(subscriptionId: subscriptionId)
                }
            }
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

// MARK: - Event Deduplication
extension RelayPool {
    /// Checks if an event has already been seen
    private func isDuplicateEvent(eventId: String) -> Bool {
        cleanupCacheIfNeeded()
        return eventCache[eventId] != nil
    }

    /// Marks an event as seen
    private func markEventAsSeen(eventId: String) {
        cleanupCacheIfNeeded()
        eventCache[eventId] = Date()
    }

    /// Cleans up expired entries from the cache
    private func cleanupCacheIfNeeded() {
        let now = Date()

        // Only cleanup periodically to avoid performance impact
        guard now.timeIntervalSince(lastCacheCleanup) > 60 else { return }
        lastCacheCleanup = now

        let cutoff = now.addingTimeInterval(-config.deduplicationCacheTTL)

        // Remove expired entries
        eventCache = eventCache.filter { $0.value > cutoff }

        // If still over limit, remove oldest entries
        if eventCache.count > config.maxDeduplicationCacheSize {
            let sortedEntries = eventCache.sorted { $0.value < $1.value }
            let entriesToRemove = eventCache.count - config.maxDeduplicationCacheSize
            for entry in sortedEntries.prefix(entriesToRemove) {
                eventCache.removeValue(forKey: entry.key)
            }
        }
    }

    /// Clears the event deduplication cache
    public func clearDeduplicationCache() {
        eventCache.removeAll()
    }

    /// Returns the current size of the deduplication cache
    public var deduplicationCacheSize: Int {
        eventCache.count
    }
}
