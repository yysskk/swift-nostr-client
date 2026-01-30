import Foundation

/// Configuration for relay pool behavior
public struct RelayPoolConfig: Sendable {
    /// Default connection configuration for new relays
    public var defaultRelayConfig: RelayConnectionConfig

    /// Maximum size of the event deduplication cache
    public var maxDeduplicationCacheSize: Int

    /// Time-to-live for cached event IDs in seconds
    public var deduplicationCacheTTL: TimeInterval

    /// Default configuration
    public static let `default` = RelayPoolConfig(
        defaultRelayConfig: .default,
        maxDeduplicationCacheSize: 10000,
        deduplicationCacheTTL: 300
    )

    public init(
        defaultRelayConfig: RelayConnectionConfig = .default,
        maxDeduplicationCacheSize: Int = 10000,
        deduplicationCacheTTL: TimeInterval = 300
    ) {
        self.defaultRelayConfig = defaultRelayConfig
        self.maxDeduplicationCacheSize = maxDeduplicationCacheSize
        self.deduplicationCacheTTL = deduplicationCacheTTL
    }
}
