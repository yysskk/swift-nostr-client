# Advanced Usage

Direct messages, encryption, relay configuration, and low-level APIs.

## Private Direct Messages (NIP-17)

NostrClient implements NIP-17 private direct messages using NIP-44 encryption and NIP-59 gift wrap for sender anonymity.

### Sending

```swift
try await client.setNsec("nsec1...")

try await client.sendDirectMessage(
    content: "Hello privately!",
    to: "recipientPubkeyHex"
)
```

### Receiving

```swift
try await client.subscribeToDirectMessages { dm in
    print("From: \(dm.senderPubkey)")
    print("Content: \(dm.content)")
}
```

### Parsing Received Gift Wraps

```swift
let dm = try await client.parseDirectMessage(giftWrapEvent)
print("Message: \(dm.content)")
```

## NIP-44 Encryption and NIP-59 Gift Wrap

For lower-level access to encryption primitives:

```swift
let senderKeyPair = try KeyPair()
let recipientPubkey = "..."

// Seal a message (NIP-44)
let sealed = try SealedMessage.seal(
    "secret message",
    for: recipientPubkey,
    using: senderKeyPair
)

// Open a sealed message
let plaintext = try SealedMessage.open(
    from: sealedPayload,
    using: recipientKeyPair
)

// Gift wrap an event (NIP-59)
let wrapped = try GiftWrap.wrap(
    event: rumorEvent,
    senderKeyPair: senderKeyPair,
    recipientPubkey: recipientPubkey
)

// Unwrap
let unwrapped = try GiftWrap.unwrap(
    giftWrap: wrappedEvent,
    recipientKeyPair: recipientKeyPair
)
```

## BIP-39 Mnemonic Key Derivation (NIP-06)

```swift
// Generate a new mnemonic and keypair
let (mnemonic, keyPair) = try KeyPair.generate(wordCount: 24)
print("Mnemonic: \(mnemonic.phrase)")

// Restore from mnemonic phrase
let restored = try KeyPair(
    mnemonicPhrase: "leader monkey parrot ring guide ...",
    passphrase: "",
    account: 0
)

// Work with Mnemonic directly
let mnemonic = try Mnemonic.generate(wordCount: 12)
let seed = try mnemonic.toSeed(passphrase: "optional passphrase")
let privateKey = try KeyDerivation.deriveNostrKey(seed: seed, account: 0)
```

## NIP-05 Internet Identifier Verification

```swift
// Verify an internet identifier
let result = try await InternetIdentifier.verify("alice@example.com")
print("Pubkey: \(result.pubkey)")
print("Relays: \(result.relays)")

// Verify against expected pubkey
try await InternetIdentifier.verify(
    "alice@example.com",
    expectedPubkey: "expected_hex..."
)

// Look up pubkey only
let pubkey = try await InternetIdentifier.lookupPubkey("alice@example.com")
```

## Contact Lists (NIP-02)

```swift
let contacts = [
    Contact(pubkey: "pubkey1", relayUrl: "wss://relay.damus.io", petname: "alice"),
    Contact(pubkey: "pubkey2")
]
try await client.publishContactList(contacts)

// Extract contacts from a kind-3 event
if let contacts = event.contacts {
    for contact in contacts {
        print("\(contact.petname ?? contact.pubkey)")
    }
}
```

## OpenTimestamps (NIP-03)

```swift
// Attach OTS attestation to an event
let ots = OpenTimestamps(base64EncodedOTS: "...")
let tags = [ots.toTag()]

// Check for OTS on received events
if let ots = event.openTimestamps {
    print("Has OTS: \(ots.otsData)")
}
```

## Relay Configuration

### Connection Configuration

```swift
let config = RelayConnectionConfig(
    connectionTimeout: 10,
    operationTimeout: 30,
    autoReconnect: true,
    maxReconnectAttempts: 10,
    initialReconnectDelay: 1,
    maxReconnectDelay: 60,
    reconnectBackoffMultiplier: 2
)
try await client.addRelay("wss://relay.damus.io", config: config)
```

### Pool Configuration

```swift
let poolConfig = RelayPoolConfig(
    maxDeduplicationCacheSize: 10000,
    deduplicationCacheTTL: 300
)
let client = NostrClient(config: poolConfig)
```

## Low-Level Relay API

### Direct Relay Connection

```swift
let connection = try RelayConnection(urlString: "wss://relay.damus.io")
await connection.connect()

try await connection.subscribe(
    subscriptionId: "sub1",
    filters: [Filter(kinds: [1], limit: 10)]
)

for await message in await connection.messages() {
    switch message {
    case .event(let subId, let event):
        print("Event: \(event.content)")
    case .endOfStoredEvents:
        print("EOSE")
    default:
        break
    }
}
```

### Manual Event Signing

```swift
let signer = EventSigner(keyPair: try KeyPair())

let unsigned = UnsignedEvent(
    pubkey: signer.publicKey,
    kind: .textNote,
    tags: [["t", "test"]],
    content: "Manually signed"
)

let signed = try signer.sign(unsigned)
let isValid = try signed.verify()
```

## Event Deduplication

``RelayPool`` automatically deduplicates events across relays using an in-memory cache. To reset:

```swift
await client.clearDeduplicationCache()
```

Cache size and TTL are configurable via ``RelayPoolConfig``.
