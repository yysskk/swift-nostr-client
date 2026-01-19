import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Represents the connection state of a relay
public enum RelayConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed(String)
}

/// Manages a WebSocket connection to a single Nostr relay
public actor RelayConnection {
    /// The relay URL
    public let url: URL

    /// Current connection state
    public private(set) var state: RelayConnectionState = .disconnected

    /// Active subscriptions
    private var subscriptions: Set<String> = []

    /// The WebSocket task
    private var webSocketTask: URLSessionWebSocketTask?

    /// URL session for WebSocket connections
    private let urlSession: URLSession

    /// Continuation for async message receiving
    private var messageContinuation: AsyncStream<RelayMessage>.Continuation?

    public init(url: URL, urlSession: URLSession = .shared) {
        self.url = url
        self.urlSession = urlSession
    }

    public init(urlString: String) throws {
        guard let url = URL(string: urlString) else {
            throw NostrError.connectionFailed("Invalid URL: \(urlString)")
        }
        self.url = url
        self.urlSession = .shared
    }

    /// Connects to the relay
    public func connect() async throws {
        guard state == .disconnected || state != .connecting else { return }

        state = .connecting

        var request = URLRequest(url: url)
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        state = .connected
        startReceiving()
    }

    /// Disconnects from the relay
    public func disconnect() {
        guard state == .connected else { return }

        state = .disconnecting
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        subscriptions.removeAll()
        state = .disconnected
    }

    /// Sends a client message to the relay
    public func send(_ message: ClientMessage) async throws {
        guard state == .connected, let task = webSocketTask else {
            throw NostrError.notConnected
        }

        let text = try message.serialize()
        try await task.send(.string(text))

        // Track subscription state
        switch message {
        case .request(let subscriptionId, _):
            subscriptions.insert(subscriptionId)
        case .close(let subscriptionId):
            subscriptions.remove(subscriptionId)
        default:
            break
        }
    }

    /// Publishes an event to the relay
    public func publish(_ event: Event) async throws {
        try await send(.event(event))
    }

    /// Subscribes to events matching the given filters
    public func subscribe(subscriptionId: String, filters: [Filter]) async throws {
        try await send(.request(subscriptionId: subscriptionId, filters: filters))
    }

    /// Unsubscribes from a subscription
    public func unsubscribe(subscriptionId: String) async throws {
        try await send(.close(subscriptionId: subscriptionId))
    }

    /// Returns an async stream of messages from this relay
    public func messages() -> AsyncStream<RelayMessage> {
        AsyncStream { continuation in
            self.messageContinuation = continuation
        }
    }

    /// Checks if a subscription is active
    public func hasSubscription(_ subscriptionId: String) -> Bool {
        subscriptions.contains(subscriptionId)
    }

    /// Returns all active subscription IDs
    public func activeSubscriptions() -> Set<String> {
        subscriptions
    }

    // MARK: - Private Methods

    private func startReceiving() {
        Task {
            while state == .connected {
                do {
                    guard let task = webSocketTask else { break }
                    let message = try await task.receive()

                    switch message {
                    case .string(let text):
                        if let relayMessage = try? RelayMessage.parse(text) {
                            messageContinuation?.yield(relayMessage)
                        }

                    case .data:
                        // Binary data not expected from Nostr relays
                        break

                    @unknown default:
                        break
                    }
                } catch {
                    if state == .connected {
                        state = .failed(error.localizedDescription)
                    }
                    break
                }
            }

            messageContinuation?.finish()
        }
    }
}

// MARK: - Equatable
extension RelayConnection: Equatable {
    public static func == (lhs: RelayConnection, rhs: RelayConnection) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Hashable
extension RelayConnection: Hashable {
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
