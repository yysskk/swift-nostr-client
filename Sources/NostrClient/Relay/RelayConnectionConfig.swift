import Foundation

/// Configuration for relay connection behavior
public struct RelayConnectionConfig: Sendable {
    /// Connection timeout in seconds
    public var connectionTimeout: TimeInterval

    /// Send/receive operation timeout in seconds
    public var operationTimeout: TimeInterval

    /// Whether to automatically reconnect on failure
    public var autoReconnect: Bool

    /// Maximum number of reconnection attempts (0 = unlimited)
    public var maxReconnectAttempts: Int

    /// Initial delay before first reconnection attempt in seconds
    public var initialReconnectDelay: TimeInterval

    /// Maximum delay between reconnection attempts in seconds
    public var maxReconnectDelay: TimeInterval

    /// Multiplier for exponential backoff
    public var reconnectBackoffMultiplier: Double

    /// Default configuration
    public static let `default` = RelayConnectionConfig(
        connectionTimeout: 10,
        operationTimeout: 30,
        autoReconnect: true,
        maxReconnectAttempts: 0,
        initialReconnectDelay: 1,
        maxReconnectDelay: 60,
        reconnectBackoffMultiplier: 2.0
    )

    public init(
        connectionTimeout: TimeInterval = 10,
        operationTimeout: TimeInterval = 30,
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 0,
        initialReconnectDelay: TimeInterval = 1,
        maxReconnectDelay: TimeInterval = 60,
        reconnectBackoffMultiplier: Double = 2.0
    ) {
        self.connectionTimeout = connectionTimeout
        self.operationTimeout = operationTimeout
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.initialReconnectDelay = initialReconnectDelay
        self.maxReconnectDelay = maxReconnectDelay
        self.reconnectBackoffMultiplier = reconnectBackoffMultiplier
    }
}
