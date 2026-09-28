import Foundation
import Testing

@testable import CookedPaper

struct DecimalCodableTests {
    private struct RequiredHolder: Codable, Equatable {
        @DecimalString var value: Decimal
    }

    private struct OptionalHolder: Codable, Equatable {
        @OptionalDecimalString var value: Decimal?
    }

    @Test func requiredDecimalStringRoundTrips() throws {
        let json = Data(#"{"value":"1234.5600"}"#.utf8)
        let decoded = try JSONDecoder().decode(RequiredHolder.self, from: json)
        #expect(decoded.value == Decimal(string: "1234.56"))

        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder().decode(RequiredHolder.self, from: reencoded)
        #expect(redecoded.value == decoded.value)
    }

    @Test func requiredDecimalStringThrowsRatherThanSilentlyDefaulting() {
        let json = Data(#"{"value":"not-a-decimal"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RequiredHolder.self, from: json)
        }
    }

    @Test func optionalDecimalStringDecodesNullAsNilRatherThanZero() throws {
        let json = Data(#"{"value":null}"#.utf8)
        let decoded = try JSONDecoder().decode(OptionalHolder.self, from: json)
        #expect(decoded.value == nil)
    }

    @Test func optionalDecimalStringRoundTripsAPresentValue() throws {
        let json = Data(#"{"value":"9.5"}"#.utf8)
        let decoded = try JSONDecoder().decode(OptionalHolder.self, from: json)
        #expect(decoded.value == Decimal(string: "9.5"))

        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder().decode(OptionalHolder.self, from: reencoded)
        #expect(redecoded == decoded)
    }

    @Test func optionalDecimalStringEncodesNilBackToNull() throws {
        let holder = OptionalHolder(value: nil)
        let data = try JSONEncoder().encode(holder)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["value"] is NSNull)
    }

    // A malformed-but-present string must decode to `nil` rather than throwing,
    // per DecimalCodable.swift's own comment: this wrapper exists specifically so
    // one bad field can't fail an entire portfolio snapshot decode.
    @Test func optionalDecimalStringMalformedValueDecodesToNilRatherThanThrowing() throws {
        let json = Data(#"{"value":"not-a-decimal"}"#.utf8)
        let decoded = try JSONDecoder().decode(OptionalHolder.self, from: json)
        #expect(decoded.value == nil)
    }
}
