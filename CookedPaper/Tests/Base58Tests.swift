import Foundation
import Testing

@testable import CookedPaper

struct Base58Tests {
    @Test func decodeRejectsAnInvalidAlphabetCharacter() {
        // '0', 'O', 'I', 'l' are deliberately excluded from the Base58 alphabet
        // to avoid visual ambiguity, matching every other Solana wallet.
        #expect(Base58.decode("0") == nil)
        #expect(Base58.decode("O") == nil)
        #expect(Base58.decode("validPrefixThenBad0Char") == nil)
    }

    @Test(arguments: [
        Data([1]),
        Data([0, 1]),
        Data([0, 0, 5, 200, 255]),
        Data([255, 254, 253, 1, 0, 0, 128]),
        Data((0..<32).map { UInt8($0) }),
    ])
    func decodeOfEncodeRoundTripsForByteArrays(_ bytes: Data) {
        let encoded = Base58.encode(bytes)
        #expect(Base58.decode(encoded) == bytes)
    }

    @Test func encodingEmitsOneLeadingOneCharacterPerLeadingZeroByte() {
        let bytes = Data([0, 0, 0, 200, 17])
        let encoded = Base58.encode(bytes)
        let leadingOnes = encoded.prefix { $0 == "1" }.count
        #expect(leadingOnes == 3)
        #expect(Base58.decode(encoded) == bytes)
    }

    @Test func knownSolanaAddressLengthByteSequenceRoundTrips() {
        let bytes = Data([
            4, 30, 200, 19, 88, 210, 1, 9, 250, 76, 3, 199, 45, 12, 88, 233,
            67, 5, 128, 44, 91, 6, 250, 12, 199, 88, 34, 210, 1, 45, 90, 254,
        ])
        #expect(bytes.count == 32)

        let encoded = Base58.encode(bytes)
        #expect(Base58.decode(encoded) == bytes)
    }

    @Test func allZeroInputRoundTrips() {
        #expect(Base58.encode(Data()) == "")
        #expect(Base58.decode("") == Data())

        #expect(Base58.encode(Data([0, 0, 0])) == "111")
        #expect(Base58.decode("111") == Data([0, 0, 0]))

        // Solana's System Program address: 32 zero bytes, base58 "1" x 32.
        let solanaSystemProgram = Data(repeating: 0, count: 32)
        let encoded = String(repeating: "1", count: 32)
        #expect(Base58.encode(solanaSystemProgram) == encoded)
        #expect(Base58.decode(encoded) == solanaSystemProgram)
    }
}
