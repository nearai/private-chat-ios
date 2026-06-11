import Foundation
import CryptoKit

/// Device-local NEAR signing key for native NEP-413 sign-in. The user authorizes
/// this key's public half on their NEAR account once (as a Full Access key); the
/// private half stays in the Keychain on this device only and signs the sign-in
/// challenge. Distinct from the conversation-export signing identity.
enum NearKeyStore {
    private static let account = "near-signing-key-ed25519"

    /// Loads the existing device key or creates and persists a new one.
    static func loadOrCreateKey() -> Curve25519.Signing.PrivateKey {
        if let existing = existingKey() { return existing }
        let key = Curve25519.Signing.PrivateKey()
        try? KeychainStore.save(key.rawRepresentation, account: account)
        return key
    }

    static func existingKey() -> Curve25519.Signing.PrivateKey? {
        guard let raw = try? KeychainStore.read(Data.self, account: account),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
            return nil
        }
        return key
    }

    /// "ed25519:<base58>" — the form a NEAR wallet expects when adding an access
    /// key, and the form sent as `publicKey` in the signed message.
    static func publicKeyString(for key: Curve25519.Signing.PrivateKey) -> String {
        "ed25519:" + NearBase58.encode(key.publicKey.rawRepresentation)
    }
}
