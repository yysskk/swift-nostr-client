# Getting Started

Install NostrClient and publish your first event.

## Installation

Add the package dependency in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yysskk/swift-nostr-client", from: "1.0.0")
]
```

Add `NostrClient` to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["NostrClient"]
)
```

Or add via Xcode: File > Add Package Dependencies > Enter the repository URL.

## Generate Keys

```swift
import NostrClient

// Generate a random keypair
let keyPair = try KeyPair()
print("npub: \(keyPair.npub)")
print("nsec: \(keyPair.nsec)")

// Import from nsec
let imported = try KeyPair(nsec: "nsec1...")

// Generate from BIP-39 mnemonic (NIP-06)
let (mnemonic, keyPairFromMnemonic) = try KeyPair.generate(wordCount: 12)
print("Mnemonic: \(mnemonic.phrase)")
```

## Connect to Relays

```swift
let client = NostrClient()

try await client.addRelays([
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://relay.nostr.band"
])
try await client.connect()
```

## Publish Events

```swift
try await client.setNsec("nsec1...")

// Text note
let event = try await client.publishTextNote(content: "Hello, Nostr!")

// Reaction
try await client.publishReaction(to: event, content: "🤙")

// Reply
try await client.publishReply(to: event, content: "Great post!")
```

## Subscribe to Events

```swift
// User timeline
let subId = try await client.subscribeToUserTimeline(pubkey: "...") { event in
    print("Note: \(event.content)")
}

// Custom filter
let filter = Filter(kinds: [1], authors: ["pubkey1"], limit: 100)
try await client.subscribe(filters: [filter]) { event in
    print("Received: \(event.id)")
}

// Unsubscribe
try await client.unsubscribe(subscriptionId: subId)
```

## Fetch Events

``NostrClient/NostrClient`` provides one-shot fetch methods that open a temporary subscription, collect matching events until all relays signal End of Stored Events (EOSE), then close the subscription and return the results.

```swift
// Fetch a specific event by ID
let event = try await client.fetchEvent(id: "eventid...")

// Fetch user metadata
let metadata = try await client.fetchMetadata(pubkey: "...")
print("Name: \(metadata?.name ?? "Unknown")")

// Fetch with custom filters
let events = try await client.fetch(filters: [
    Filter(kinds: [1], authors: ["pubkey1"], limit: 50)
])
```
