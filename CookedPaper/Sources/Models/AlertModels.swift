import Foundation

// Alert rules and push registration: `packages/api-types/src/social.ts`
// (`Alert`, `AlertRule`, `CreateAlertBody`, `UpdateAlertBody`) plus the APNs token
// routes. Only `price_crossed` rules are created by this app, but `GET
// /social/alerts` returns every kind the account has (made on web, say), so the
// rule decodes loosely: a kind this app doesn't draw still lists by name.

enum PriceAlertDirection: String, Codable, CaseIterable, Identifiable {
    case above, below
    var id: String { rawValue }
    var title: String { self == .above ? "Above" : "Below" }
    /// "rises above" / "falls below", for sentences.
    var verb: String { self == .above ? "rises above" : "falls below" }
}

struct PriceAlertRule: Decodable {
    let kind: String
    /// `price_crossed` (and `token_bought_by_following`) only.
    let mint: String?
    /// `price_crossed` only: "above" or "below".
    let direction: String?
    /// `price_crossed` only: the threshold in USD, a decimal string on the wire.
    @OptionalDecimalString var priceUsd: Decimal?

    var isPriceCrossed: Bool { kind == "price_crossed" }
    var priceDirection: PriceAlertDirection? { direction.flatMap(PriceAlertDirection.init(rawValue:)) }
}

struct PriceAlert: Decodable, Identifiable {
    let id: String
    let name: String
    let rule: PriceAlertRule
    /// "push", "in_app" or "email".
    let channel: String
    let isActive: Bool
    let cooldownSeconds: Int
    let lastFiredAt: String?
    let createdAt: String

    /// A `price_crossed` rule with everything the app needs to draw and describe it.
    var isPriceAlert: Bool {
        rule.isPriceCrossed && rule.mint != nil && rule.priceUsd != nil && rule.priceDirection != nil
    }

    var lastFiredDate: Date? { lastFiredAt.flatMap(PriceAlert.parseDate) }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parseDate(_ raw: String) -> Date? {
        isoFormatter.date(from: raw) ?? isoFormatterFractional.date(from: raw)
    }
}

/// `GET /social/alerts`.
struct PriceAlertListResponse: Decodable {
    let alerts: [PriceAlert]
}

/// `POST`, `PATCH` and `DELETE /social/alerts…`.
struct PriceAlertResponse: Decodable {
    let alert: PriceAlert
}

/// The `price_crossed` arm of `AlertRule`. `priceUsd` must be a plain decimal
/// string (`^-?\d+(\.\d+)?$`, no exponent) — see `PriceAlertMath.plain`.
struct PriceCrossedRuleBody: Encodable {
    var kind = "price_crossed"
    let mint: String
    let direction: PriceAlertDirection
    let priceUsd: String
}

/// `POST /social/alerts`.
struct CreatePriceAlertBody: Encodable {
    /// 1–64 characters.
    let name: String
    let rule: PriceCrossedRuleBody
    var channel = "push"
    /// 0–86,400; the server's default is 300.
    var cooldownSeconds = 300
}

/// `PATCH /social/alerts/:id` — only the active switch is changed from this app.
struct UpdatePriceAlertBody: Encodable {
    let isActive: Bool
}

/// `POST /social/apns-tokens`.
struct RegisterAPNsTokenBody: Encodable {
    /// The APNs device token, lowercase hex.
    let deviceToken: String
    /// "sandbox" for DEBUG builds (development aps-environment), else "production".
    let environment: String
}

/// `POST /social/apns-tokens/revoke`.
struct RevokeAPNsTokenBody: Encodable {
    let deviceToken: String
}

/// `{ "ok": true }`.
struct OKResponse: Decodable {
    let ok: Bool?
}

/// Formatting and parsing for alert thresholds. Prices go to the server as plain
/// decimal strings, never `Double`s and never in exponent notation.
enum PriceAlertMath {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// What someone typed, accepting either decimal separator. Nil unless > 0.
    static func parse(_ text: String) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "$", with: "")
        guard !normalized.isEmpty, let value = Decimal(string: normalized, locale: posix), value > 0 else { return nil }
        return value
    }

    /// `value` rounded to about `significantDigits` significant digits (at least two
    /// decimals) as a plain decimal string: 1.8342, 0.00002314, 1234.5.
    static func plain(_ value: Decimal, significantDigits: Int = 6) -> String {
        guard value > 0 else { return "0" }
        let magnitude = NSDecimalNumber(decimal: value).doubleValue
        let exponent = Int(floor(log10(magnitude)))
        let scale = max(2, significantDigits - 1 - exponent)
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, scale, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    /// `price` moved by `percent` (e.g. 10 or -25).
    static func offset(_ price: Decimal, percent: Int) -> Decimal {
        price * (1 + Decimal(percent) / 100)
    }
}
