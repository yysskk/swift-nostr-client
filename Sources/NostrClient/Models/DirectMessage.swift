import Foundation

/// NIP-17 Private Direct Message
/// https://github.com/nostr-protocol/nips/blob/master/17.md
public struct DirectMessage: Sendable, Identifiable, Hashable {
    /// Unique identifier (from the rumor event id)
    public var id: String { rumorId }

    /// The rumor event ID
    public let rumorId: String

    /// The sender's public key (hex)
    public let senderPubkey: String

    /// The recipient's public key (hex)
    public let recipientPubkey: String

    /// The message content
    public let content: String

    /// The timestamp when the message was created
    public let createdAt: Date

    /// Optional subject/title for the conversation
    public let subject: String?

    /// Optional reply reference (event ID being replied to)
    public let replyTo: String?

    public init(
        rumorId: String,
        senderPubkey: String,
        recipientPubkey: String,
        content: String,
        createdAt: Date,
        subject: String? = nil,
        replyTo: String? = nil
    ) {
        self.rumorId = rumorId
        self.senderPubkey = senderPubkey
        self.recipientPubkey = recipientPubkey
        self.content = content
        self.createdAt = createdAt
        self.subject = subject
        self.replyTo = replyTo
    }
}

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

/// Parser for received NIP-17 direct messages
public struct DirectMessageParser: Sendable {
    private let recipientKeyPair: KeyPair

    public init(keyPair: KeyPair) {
        self.recipientKeyPair = keyPair
    }

    /// Parses a gift-wrapped event into a DirectMessage
    /// - Parameter giftWrap: The gift-wrapped event
    /// - Returns: The parsed DirectMessage
    public func parse(_ giftWrap: Event) throws -> DirectMessage {
        let unwrapped = try GiftWrap.unwrap(
            giftWrap: giftWrap,
            recipientKeyPair: recipientKeyPair
        )

        let rumor = unwrapped.event

        guard rumor.kind == Event.Kind.privateDirectMessage.rawValue else {
            throw NostrError.invalidData
        }

        // Extract recipient from p tag
        let recipientPubkey = rumor.tags
            .first { $0.first == "p" && $0.count >= 2 }
            .map { $0[1] } ?? recipientKeyPair.publicKeyHex

        // Extract optional subject
        let subject = rumor.tags
            .first { $0.first == "subject" && $0.count >= 2 }
            .map { $0[1] }

        // Extract optional reply reference
        let replyTo = rumor.tags
            .first { $0.first == "e" && $0.count >= 4 && $0[3] == "reply" }
            .map { $0[1] }

        return DirectMessage(
            rumorId: rumor.id,
            senderPubkey: unwrapped.senderPubkey,
            recipientPubkey: recipientPubkey,
            content: rumor.content,
            createdAt: Date(timeIntervalSince1970: TimeInterval(rumor.createdAt)),
            subject: subject,
            replyTo: replyTo
        )
    }
}
