import Foundation

/// Lowercase hex <-> `Data` conversion, scoped to this module.
///
/// `NostrClient` has equivalent helpers but they are `internal`, so this module carries its own.
enum NWCHex {
    /// Decodes a hex string into bytes, or `nil` if it is not valid lowercase/uppercase hex with an
    /// even number of digits.
    static func data(from hex: String) -> Data? {
        let hex = hex.lowercased()
        guard hex.count % 2 == 0 else { return nil }

        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    /// Encodes bytes as a lowercase hex string.
    static func string(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `hex` decodes to exactly `byteCount` bytes.
    static func isValid(_ hex: String, byteCount: Int) -> Bool {
        guard let data = data(from: hex) else { return false }
        return data.count == byteCount
    }
}
