import XCTest
import CryptoKit
@testable import NEARPrivateChat

extension PrivateChatCoreTests {

    // MARK: - Borsh / digest layout

    /// Rebuilds the exact prefix + Borsh buffer by hand and asserts that its sha256
    /// equals `signingDigest`. Locks the field order and encoding against the spec.
    func testSigningDigestMatchesHandAssembledBorshBytes() {
        let nonce = Data(0..<32)
        let payload = NEP413Payload(
            message: "Sign in to NEAR AI",
            nonce: nonce,
            recipient: "app.near",
            callbackUrl: nil
        )

        // 2147484061 (= 2^31 + 413) as Borsh u32 little-endian is 0x8000019D -> 9D 01 00 80.
        var expected = Data()
        expected.append(contentsOf: [0x9D, 0x01, 0x00, 0x80])           // u32le prefix 2147484061
        expected.append(contentsOf: [0x12, 0x00, 0x00, 0x00])           // message len = 18
        expected.append(Data("Sign in to NEAR AI".utf8))                // message utf8
        expected.append(nonce)                                          // 32 nonce bytes, no prefix
        expected.append(contentsOf: [0x08, 0x00, 0x00, 0x00])           // recipient len = 8
        expected.append(Data("app.near".utf8))                          // recipient utf8
        expected.append(0x00)                                           // callbackUrl = None

        let expectedDigest = Data(SHA256.hash(data: expected))
        XCTAssertEqual(NEP413Signer.signingDigest(payload), expectedDigest)
        XCTAssertEqual(NEP413Signer.signingDigest(payload).count, 32)

        // Independent guard: the prefix is u32-little-endian of 2147484061.
        let prefix = withUnsafeBytes(of: UInt32(2_147_484_061).littleEndian) { Data($0) }
        XCTAssertEqual(Array(prefix), [0x9D, 0x01, 0x00, 0x80])
    }

    /// A non-nil callbackUrl emits `0x01` + Borsh string instead of the `0x00` tag.
    func testSigningDigestEncodesSomeCallbackUrl() {
        let nonce = Data(repeating: 0xAB, count: 32)
        let payload = NEP413Payload(
            message: "m",
            nonce: nonce,
            recipient: "r",
            callbackUrl: "ok"
        )

        var expected = Data()
        expected.append(contentsOf: [0x9D, 0x01, 0x00, 0x80])
        expected.append(contentsOf: [0x01, 0x00, 0x00, 0x00])           // "m"
        expected.append(Data("m".utf8))
        expected.append(nonce)
        expected.append(contentsOf: [0x01, 0x00, 0x00, 0x00])           // "r"
        expected.append(Data("r".utf8))
        expected.append(0x01)                                           // Option::Some
        expected.append(contentsOf: [0x02, 0x00, 0x00, 0x00])           // "ok"
        expected.append(Data("ok".utf8))

        XCTAssertEqual(NEP413Signer.signingDigest(payload), Data(SHA256.hash(data: expected)))
    }

    // MARK: - Base58

    func testBase58KnownVectors() {
        XCTAssertEqual(NearBase58.encode(Data([0])), "1")
        XCTAssertEqual(NearBase58.encode(Data([0, 0])), "11")
        XCTAssertEqual(NearBase58.encode(Data()), "")
        // 0x0000287fb4cd → "11233QC4" (Bitcoin base58 reference vector, 2 leading zero bytes).
        XCTAssertEqual(NearBase58.encode(Data([0x00, 0x00, 0x28, 0x7f, 0xb4, 0xcd])), "11233QC4")
    }

    func testBase58RoundTripIncludingLeadingZeros() {
        let vectors: [Data] = [
            Data(),
            Data([0]),
            Data([0, 0, 0]),
            Data([0, 1, 2, 3, 255]),
            Data([255, 255, 255, 255]),
            Data((0..<32).map { UInt8($0) }),
            Data([0, 0, 7, 13, 200, 99, 1])
        ]
        for vector in vectors {
            let encoded = NearBase58.encode(vector)
            XCTAssertEqual(NearBase58.decode(encoded), vector, "round-trip failed for \(Array(vector))")
        }
    }

    func testBase58RejectsInvalidCharacters() {
        // '0', 'O', 'I', 'l' are not in the alphabet.
        XCTAssertNil(NearBase58.decode("0"))
        XCTAssertNil(NearBase58.decode("O"))
        XCTAssertNil(NearBase58.decode("I"))
        XCTAssertNil(NearBase58.decode("l"))
        XCTAssertNil(NearBase58.decode("abc!"))
        XCTAssertNil(NearBase58.decode("héllo"))
    }

    func testBase58EncodesEd25519PublicKeyToExpectedLength() {
        let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        XCTAssertEqual(key.count, 32)
        let encoded = NearBase58.encode(key)
        XCTAssertEqual(NearBase58.decode(encoded), key)
        XCTAssertFalse(encoded.isEmpty)
    }

    // MARK: - sign()

    func testSignProducesVerifiableWireMessage() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let payload = NEP413Payload(
            message: "Sign in to NEAR AI",
            nonce: NEP413Signer.randomNonce(),
            recipient: "ai.near.privatechat.ios",
            callbackUrl: nil
        )

        let signed = NEP413Signer.sign(
            payload: payload,
            accountId: "alice.near",
            privateKey: privateKey
        )

        XCTAssertEqual(signed.accountId, "alice.near")
        XCTAssertTrue(signed.publicKey.hasPrefix("ed25519:"))

        // publicKey base58 body decodes to the 32-byte raw key.
        let base58Body = String(signed.publicKey.dropFirst("ed25519:".count))
        XCTAssertEqual(NearBase58.decode(base58Body), privateKey.publicKey.rawRepresentation)

        // signature is base64 of a 64-byte Ed25519 signature.
        let signatureBytes = try XCTUnwrap(Data(base64Encoded: signed.signature))
        XCTAssertEqual(signatureBytes.count, 64)

        // The signature verifies against the public key over the signing digest.
        let digest = NEP413Signer.signingDigest(payload)
        XCTAssertTrue(privateKey.publicKey.isValidSignature(signatureBytes, for: digest))
    }

    func testRandomNonceIs32BytesAndUnique() {
        let a = NEP413Signer.randomNonce()
        let b = NEP413Signer.randomNonce()
        XCTAssertEqual(a.count, 32)
        XCTAssertEqual(b.count, 32)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Encodable wire shape

    func testSignedMessageEncodesCamelCaseKeys() throws {
        let message = NEP413SignedMessage(
            accountId: "alice.near",
            publicKey: "ed25519:abc",
            signature: "c2ln"
        )
        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(Set(object.keys), ["accountId", "publicKey", "signature"])
        XCTAssertEqual(object["accountId"], "alice.near")
        XCTAssertEqual(object["publicKey"], "ed25519:abc")
        XCTAssertEqual(object["signature"], "c2ln")
    }
}
