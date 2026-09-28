import Foundation

/// Every money/quantity field in the Cooked API is a decimal-formatted **string**,
/// never a JSON number — Postgres numeric columns cross the wire as strings
/// specifically to avoid float corruption of large-precision quantities and prices
/// (confirmed across `packages/api-types/src/paper.ts`, `portfolio.ts`, `tokens.ts`).
/// These wrappers are the one place that string gets turned into a `Decimal`, so nothing
/// downstream ever risks a `Double` round-trip on a number that means money.
private let decimalLocale = Locale(identifier: "en_US_POSIX")

/// A required decimal-string field, e.g. `cashUsd`, `qty`.
@propertyWrapper
struct DecimalString: Codable, Hashable {
    var wrappedValue: Decimal

    init(wrappedValue: Decimal) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = Decimal(string: raw, locale: decimalLocale) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a decimal string, got \"\(raw)\""
            )
        }
        wrappedValue = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: wrappedValue).stringValue)
    }
}

/// A nullable decimal-string field. **Null is a stated absence, never zero** — the
/// API's own convention (e.g. `unrealizedPnlUsd` is null exactly when nothing has
/// priced the position, not when the position is flat). Render `nil` as "—" or
/// "unpriced", never coerce it to `0`.
@propertyWrapper
struct OptionalDecimalString: Codable, Hashable {
    var wrappedValue: Decimal?

    init(wrappedValue: Decimal?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
            return
        }
        let raw = try container.decode(String.self)
        // A malformed-but-present string decodes to nil rather than throwing: this
        // wrapper's whole job is keeping one bad field from failing an entire
        // portfolio snapshot decode.
        wrappedValue = Decimal(string: raw, locale: decimalLocale)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(NSDecimalNumber(decimal: wrappedValue).stringValue)
        } else {
            try container.encodeNil()
        }
    }
}

extension Decimal {
    /// `$1,234.56`-style formatting for a USD figure.
    func usdString(fractionDigits: Int = 2) -> String {
        formatted(.currency(code: "USD").precision(.fractionLength(fractionDigits)))
    }

    /// `+12.34%` / `-3.20%`-style formatting, sign always shown.
    func signedPercentString(fractionDigits: Int = 2) -> String {
        let sign = self >= 0 ? "+" : ""
        return "\(sign)\(formatted(.number.precision(.fractionLength(fractionDigits))))%"
    }
}

extension KeyedDecodingContainer {
    /// A missing key decodes as nil, like a plain `Decimal?` would, so additive
    /// server fields (e.g. `leveragedValueUsd`) don't break decoding older responses.
    func decode(_ type: OptionalDecimalString.Type, forKey key: Key) throws -> OptionalDecimalString {
        try decodeIfPresent(type, forKey: key) ?? OptionalDecimalString(wrappedValue: nil)
    }
}
