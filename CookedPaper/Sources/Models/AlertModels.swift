import Foundation

/// Mirrors `AlertRule` in `packages/api-types/src/social.ts` — a five-kind
/// discriminated union on `kind`, because alerts can be created from the web app
/// too. This app only ever constructs and only ever renders-as-editable the
/// `price_crossed` kind, so every other kind (`wallet_trades`, `wallet_trades_over`,
/// `token_bought_by_following`, `trending_token`) decodes to `.unsupported(kind:)`
/// rather than failing the decode — one alert this app doesn't understand must not
/// take the whole list down with it. Same discriminated-union-on-a-string shape as
/// `LivePricing` in `LiveModels.swift`; this follows that file's decode style.
enum AlertRule: Codable, Hashable {
    case priceCrossed(mint: String, direction: Direction, priceUsd: Decimal)
    case unsupported(kind: String)

    enum Direction: String, Codable, Hashable {
        case above, below
    }

    private enum CodingKeys: String, CodingKey {
        case kind, mint, direction, priceUsd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        guard kind == "price_crossed" else {
            self = .unsupported(kind: kind)
            return
        }
        let mint = try container.decode(String.self, forKey: .mint)
        let direction = try container.decode(Direction.self, forKey: .direction)
        // Reuse `DecimalString`'s own decimal-string parsing rather than re-hand-roll
        // it here — same wire format, same locale rule, one place that can drift.
        let priceUsd = try container.decode(DecimalString.self, forKey: .priceUsd).wrappedValue
        self = .priceCrossed(mint: mint, direction: direction, priceUsd: priceUsd)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .priceCrossed(let mint, let direction, let priceUsd):
            try container.encode("price_crossed", forKey: .kind)
            try container.encode(mint, forKey: .mint)
            try container.encode(direction, forKey: .direction)
            try container.encode(DecimalString(wrappedValue: priceUsd), forKey: .priceUsd)
        case .unsupported(let kind):
            // This app never re-sends a rule it did not build itself — there is no
            // update-in-place here, only create/delete — so this arm only exists to
            // make the type's `Encodable` conformance total.
            try container.encode(kind, forKey: .kind)
        }
    }
}

enum AlertChannel: String, Codable, Hashable {
    case push, inApp = "in_app", email
}

/// Mirrors `Alert` in `packages/api-types/src/social.ts`. Named `PriceAlert` rather
/// than the bare `Alert` the backend uses — SwiftUI still exports a deprecated
/// `Alert` struct, and this target has never been compiled, so this sidesteps a name
/// collision rather than risk one. Only the Swift type name differs: the JSON keys
/// below (`alerts`, `alert`) are unchanged, so the wire format matches exactly.
struct PriceAlert: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let rule: AlertRule
    let channel: AlertChannel
    let isActive: Bool
    let cooldownSeconds: Int
    let lastFiredAt: String?
    let createdAt: String
}

struct AlertListResponse: Decodable {
    let alerts: [PriceAlert]
}

struct AlertResponse: Decodable {
    let alert: PriceAlert
}

/// What this app sends to `POST /social/alerts`. `channel` is always `.inApp` here —
/// see `AlertsAPI.create`.
struct CreateAlertBody: Encodable {
    let name: String
    let rule: AlertRule
    let channel: AlertChannel
    let cooldownSeconds: Int
}
