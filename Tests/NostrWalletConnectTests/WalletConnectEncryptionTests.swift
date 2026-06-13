import Foundation
import NostrClient
import Testing

@testable import NostrWalletConnect

@Suite("WalletConnectEncryption Tests")
struct WalletConnectEncryptionTests {
    @Test("scheme raw values match the NIP-47 wire tokens")
    func rawValues() {
        #expect(WalletConnectEncryption.nip44.rawValue == "nip44_v2")
        #expect(WalletConnectEncryption.nip04.rawValue == "nip04")
        #expect(WalletConnectEncryption(rawValue: "nip44_v2") == .nip44)
        #expect(WalletConnectEncryption(rawValue: "nip04") == .nip04)
        #expect(WalletConnectEncryption(rawValue: "aes") == nil)
    }

    @Test("NIP-44 round-trips through the cipher", arguments: [WalletConnectEncryption.nip44, .nip04])
    func roundTrip(scheme: WalletConnectEncryption) throws {
        let client = try KeyPair()
        let wallet = try KeyPair()
        let cipher = WalletConnectCipher(scheme)
        let message = #"{"method":"get_balance","params":{}}"#

        let payload = try cipher.encrypt(message, recipientPubkey: wallet.publicKeyHex, sender: client)
        let decrypted = try cipher.decrypt(payload, senderPubkey: client.publicKeyHex, recipient: wallet)

        #expect(decrypted == message)
    }

    @Test("a NIP-04 payload is shaped differently from a NIP-44 payload")
    func payloadShapes() throws {
        let client = try KeyPair()
        let wallet = try KeyPair()

        let nip04 = try WalletConnectCipher(.nip04).encrypt("hi", recipientPubkey: wallet.publicKeyHex, sender: client)
        let nip44 = try WalletConnectCipher(.nip44).encrypt("hi", recipientPubkey: wallet.publicKeyHex, sender: client)

        #expect(nip04.contains("?iv="))
        #expect(!nip44.contains("?iv="))
    }

    @Test("decrypting with the wrong scheme fails")
    func crossSchemeFails() throws {
        let client = try KeyPair()
        let wallet = try KeyPair()

        let nip04Payload = try WalletConnectCipher(.nip04)
            .encrypt("hi", recipientPubkey: wallet.publicKeyHex, sender: client)
        #expect(throws: (any Error).self) {
            try WalletConnectCipher(.nip44).decrypt(nip04Payload, senderPubkey: client.publicKeyHex, recipient: wallet)
        }

        let nip44Payload = try WalletConnectCipher(.nip44)
            .encrypt("hi", recipientPubkey: wallet.publicKeyHex, sender: client)
        #expect(throws: (any Error).self) {
            try WalletConnectCipher(.nip04).decrypt(nip44Payload, senderPubkey: client.publicKeyHex, recipient: wallet)
        }
    }

    @Test("an invalid recipient public key is rejected")
    func invalidPubkey() throws {
        let client = try KeyPair()
        #expect(throws: NostrError.invalidPublicKey) {
            try WalletConnectCipher(.nip04).encrypt("hi", recipientPubkey: "deadbeef", sender: client)
        }
    }
}
