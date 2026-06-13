import Foundation

/// Errors raised by the NostrWalletConnect module.
///
/// Additional cases are introduced alongside the request/response and transport layers; this file
/// grows as those layers land.
public enum WalletConnectError: Error, LocalizedError, Sendable, Equatable {
    /// A `nostr+walletconnect://` connection string could not be parsed or failed validation.
    case invalidURI(reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURI(let reason):
            return "Invalid Nostr Wallet Connect URI: \(reason)"
        }
    }
}
