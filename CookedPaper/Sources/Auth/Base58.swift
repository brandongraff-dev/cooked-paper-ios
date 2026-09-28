import Foundation

/// The Bitcoin-alphabet Base58 codec Solana addresses and signatures use. Vendored
/// because neither Foundation nor Privy's SDK ships one — Privy's embedded-wallet
/// `signMessage` speaks base64 in and out, but apps/api's SIWS verifier (shared by
/// the external-wallet and embedded-wallet paths — `WalletProof` in
/// `packages/embedded-wallet/src/contract.ts`) expects a base58 signature, matching
/// every other Solana wallet's convention.
enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
    private static let alphabetMap: [UInt8: Int] = {
        var map = [UInt8: Int]()
        for (index, char) in alphabet.enumerated() { map[char] = index }
        return map
    }()

    static func encode(_ bytes: Data) -> String {
        // Starts empty, not seeded with a placeholder zero digit — a digit is only
        // ever appended on a real nonzero carry, so all-zero input naturally leaves
        // this empty and contributes nothing beyond the leading-'1' prefix below.
        var digits = [UInt8]()
        for byte in bytes {
            var carry = Int(byte)
            for j in 0..<digits.count {
                carry += Int(digits[j]) << 8
                digits[j] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }

        // Preserve leading zero bytes as leading '1's, Base58's own convention.
        let leadingZeros = bytes.prefix { $0 == 0 }.count
        let leadingOnes = [UInt8](repeating: alphabet[0], count: leadingZeros)
        let body = digits.reversed().map { alphabet[Int($0)] }
        return String(decoding: leadingOnes + body, as: UTF8.self)
    }

    static func decode(_ string: String) -> Data? {
        // Same reasoning as encode's `digits`: empty rather than zero-seeded, so an
        // all-'1' string (value zero) leaves this empty instead of one byte too long.
        var bytes = [UInt8]()
        for char in string.utf8 {
            guard let value = alphabetMap[char] else { return nil }
            var carry = value
            for j in 0..<bytes.count {
                carry += Int(bytes[j]) * 58
                bytes[j] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }

        let leadingOnes = string.utf8.prefix { $0 == alphabet[0] }.count
        let leadingZeros = [UInt8](repeating: 0, count: leadingOnes)
        return Data(leadingZeros + bytes.reversed())
    }
}
