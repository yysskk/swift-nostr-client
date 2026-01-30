import Foundation

/// Builder for creating NIP-17 direct message events
public struct DirectMessageBuilder: Sendable {
    private let senderKeyPair: KeyPair

    public init(keyPair: KeyPair) {
        self.senderKeyPair = keyPair
    }

    /// Creates a gift-wrapped direct message event ready for publishing
    /// - Parameters:
    ///   - content: The message content
    ///   - recipientPubkey: The recipient's public key (hex)
    ///   - subject: Optional conversation subject
    ///   - replyTo: Optional event ID to reply to
    /// - Returns: A gift-wrapped event for the recipient
    public func createMessage(
        content: String,
        to recipientPubkey: String,
        subject: String? = nil,
        replyTo: String? = nil
    ) throws -> Event {
        // Build tags
        var tags: [[String]] = [
            ["p", recipientPubkey]
        ]

        if let subject = subject {
            tags.append(["subject", subject])
        }

        if let replyTo = replyTo {
            tags.append(["e", replyTo, "", "reply"])
        }

        // Create the unsigned rumor event (kind 14)
        let unsigned = UnsignedEvent(
            pubkey: senderKeyPair.publicKeyHex,
            kind: .privateDirectMessage,
            tags: tags,
            content: content
        )

        // Sign it to get a valid event with ID
        let signer = EventSigner(keyPair: senderKeyPair)
        let signedRumor = try signer.sign(unsigned)

        // Gift wrap for recipient
        return try GiftWrap.wrap(
            event: signedRumor,
            senderKeyPair: senderKeyPair,
            recipientPubkey: recipientPubkey
        )
    }

    /// Creates gift-wrapped events for a group message (sends to multiple recipients)
    /// Each recipient gets their own gift-wrapped copy
    /// - Parameters:
    ///   - content: The message content
    ///   - recipientPubkeys: The recipients' public keys (hex)
    ///   - subject: Optional conversation subject
    /// - Returns: Array of gift-wrapped events, one for each recipient
    public func createGroupMessage(
        content: String,
        to recipientPubkeys: [String],
        subject: String? = nil
    ) throws -> [Event] {
        // Build tags with all recipients
        var tags: [[String]] = recipientPubkeys.map { ["p", $0] }

        if let subject = subject {
            tags.append(["subject", subject])
        }

        // Create the unsigned rumor event
        let unsigned = UnsignedEvent(
            pubkey: senderKeyPair.publicKeyHex,
            kind: .privateDirectMessage,
            tags: tags,
            content: content
        )

        let signer = EventSigner(keyPair: senderKeyPair)
        let signedRumor = try signer.sign(unsigned)

        // Gift wrap for each recipient (including sender for their copy)
        var giftWraps: [Event] = []

        for recipientPubkey in recipientPubkeys {
            let wrapped = try GiftWrap.wrap(
                event: signedRumor,
                senderKeyPair: senderKeyPair,
                recipientPubkey: recipientPubkey
            )
            giftWraps.append(wrapped)
        }

        // Also create a copy for the sender
        let senderCopy = try GiftWrap.wrap(
            event: signedRumor,
            senderKeyPair: senderKeyPair,
            recipientPubkey: senderKeyPair.publicKeyHex
        )
        giftWraps.append(senderCopy)

        return giftWraps
    }
}
