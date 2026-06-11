import Foundation
import CryptoKit

/// Wire object for `signed_message` in `POST /v1/auth/near`. Serializes to the
/// camelCase `NearSignedMessageJson` the backend expects (`accountId`, `publicKey`,
/// `signature`), mirroring the object `wallet.signMessage(...)` returns on web.
struct NEP413SignedMessage: Encodable {
    /// `<account>.near`.
    let accountId: String
    /// `ed25519:<base58 of the 32-byte raw public key>`.
    let publicKey: String
    /// Base64 of the 64-byte Ed25519 signature.
    let signature: String
}

/// Inputs to the NEP-413 signing payload. `nonce` must be exactly 32 bytes;
/// `callbackUrl` is `nil` for the native flow (encoded as a Borsh `None`).
struct NEP413Payload {
    let message: String
    let nonce: Data
    let recipient: String
    let callbackUrl: String?
}

/// NEP-413 message signing (https://github.com/near/NEPs/blob/master/neps/nep-0413.md).
///
/// Signing input is `sha256(PREFIX || borsh(payload))`, signed with Ed25519. The
/// resulting 32-byte digest is passed directly to CryptoKit's `Curve25519.Signing`,
/// which signs the supplied bytes as the message.
enum NEP413Signer {
    /// Borsh discriminant `2^31 + 413`, serialized as a u32 little-endian prefix
    /// (`[0x1D, 0x9D, 0x00, 0x80]`).
    private static let prefixTag: UInt32 = 2_147_484_061

    /// `sha256(PREFIX || borsh(payload))` — the 32-byte digest that gets Ed25519-signed.
    static func signingDigest(_ payload: NEP413Payload) -> Data {
        var buffer = Data()
        buffer.append(u32LittleEndian(prefixTag))
        buffer.append(borshString(payload.message))
        buffer.append(payload.nonce) // [u8; 32], no length prefix.
        buffer.append(borshString(payload.recipient))
        if let callbackUrl = payload.callbackUrl {
            buffer.append(0x01) // Option::Some
            buffer.append(borshString(callbackUrl))
        } else {
            buffer.append(0x00) // Option::None
        }
        return Data(SHA256.hash(data: buffer))
    }

    /// Signs a payload, producing the wire object. `publicKey` derives from the
    /// private key's 32-byte raw representation.
    ///
    /// `Curve25519.Signing.PrivateKey.signature(for:)` only throws on an internal
    /// RNG failure, which cannot occur in practice; the empty-signature fallback
    /// exists solely to keep this entry point non-throwing for the auth flow, and
    /// the server rejects a malformed signature rather than admitting a bad login.
    static func sign(
        payload: NEP413Payload,
        accountId: String,
        privateKey: Curve25519.Signing.PrivateKey
    ) -> NEP413SignedMessage {
        let digest = signingDigest(payload)
        let signature = (try? privateKey.signature(for: digest)) ?? Data()
        let publicKey = "ed25519:" + NearBase58.encode(privateKey.publicKey.rawRepresentation)
        return NEP413SignedMessage(
            accountId: accountId,
            publicKey: publicKey,
            signature: Data(signature).base64EncodedString()
        )
    }

    /// 32 cryptographically random bytes, suitable for the NEP-413 `nonce`.
    static func randomNonce() -> Data {
        var nonce = Data(count: 32)
        nonce.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                _ = SecRandomCopyBytes(kSecRandomDefault, 32, base)
            }
        }
        return nonce
    }

    /// The nonce `/v1/auth/near` requires: `Date.now()` milliseconds as a
    /// big-endian UInt64 in bytes 0–7, then 24 random bytes (mirrors the web
    /// `UY()` builder). The server rejects a fully-random nonce with
    /// "Invalid signature timestamp: timestamp out of range".
    static func timestampNonce(now: Date = Date()) -> Data {
        var nonce = Data(count: 32)
        let millis = UInt64(now.timeIntervalSince1970 * 1000)
        let bigEndian = withUnsafeBytes(of: millis.bigEndian) { Data($0) }
        nonce.replaceSubrange(0..<8, with: bigEndian)
        var random = Data(count: 24)
        random.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                _ = SecRandomCopyBytes(kSecRandomDefault, 24, base)
            }
        }
        nonce.replaceSubrange(8..<32, with: random)
        return nonce
    }

    /// Borsh string: u32 little-endian byte length followed by UTF-8 bytes.
    private static func borshString(_ value: String) -> Data {
        let utf8 = Data(value.utf8)
        return u32LittleEndian(UInt32(utf8.count)) + utf8
    }

    private static func u32LittleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
