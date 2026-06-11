import Foundation

/// Base58 codec on the Bitcoin/NEAR alphabet. Used to render the wire `publicKey`
/// as `ed25519:<base58>` and to decode `ed25519:`-prefixed keys.
///
/// Constraints:
/// - Alphabet is exactly `123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz`
///   (no `0`, `O`, `I`, `l`).
/// - Each leading zero byte maps to one leading `1`, and vice versa, so encode/decode
///   round-trips byte arrays with leading zeros.
/// - `decode` returns `nil` for any character outside the alphabet.
enum NearBase58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    /// Reverse lookup: ASCII value -> digit value, or 0xFF for characters not in the alphabet.
    private static let decodeTable: [UInt8] = {
        var table = [UInt8](repeating: 0xFF, count: 128)
        for (index, character) in alphabet.enumerated() {
            if let ascii = character.asciiValue {
                table[Int(ascii)] = UInt8(index)
            }
        }
        return table
    }()

    static func encode(_ data: Data) -> String {
        if data.isEmpty { return "" }

        // Count leading zero bytes; each becomes a leading '1'.
        var leadingZeros = 0
        for byte in data {
            if byte == 0 { leadingZeros += 1 } else { break }
        }

        // Base-256 -> base-58 by repeated division of the big-endian byte buffer.
        var digits: [UInt8] = []
        for byte in data {
            var carry = Int(byte)
            for index in digits.indices {
                carry += Int(digits[index]) << 8
                digits[index] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }

        var characters = [Character]()
        characters.reserveCapacity(leadingZeros + digits.count)
        for _ in 0..<leadingZeros { characters.append(alphabet[0]) }
        // `digits` holds least-significant first; emit most-significant first.
        for digit in digits.reversed() { characters.append(alphabet[Int(digit)]) }
        return String(characters)
    }

    static func decode(_ string: String) -> Data? {
        if string.isEmpty { return Data() }

        var leadingOnes = 0
        for character in string {
            if character == alphabet[0] { leadingOnes += 1 } else { break }
        }

        // Base-58 -> base-256 by repeated multiply-accumulate.
        var bytes: [UInt8] = []
        for character in string {
            guard let ascii = character.asciiValue, ascii < 128 else { return nil }
            let value = decodeTable[Int(ascii)]
            if value == 0xFF { return nil }

            var carry = Int(value)
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }

        var result = [UInt8](repeating: 0, count: leadingOnes)
        // `bytes` holds least-significant first; the big-endian value is its reverse.
        result.append(contentsOf: bytes.reversed())
        return Data(result)
    }
}
