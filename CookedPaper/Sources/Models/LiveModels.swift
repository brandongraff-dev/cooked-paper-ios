import Foundation

/// A live per-position mark. The API deliberately discriminates on `state` rather
/// than letting a client compute a fake price/PnL when nothing has quoted the mint —
/// `.unmeasured` carries no `markPriceUsd` at all, on purpose.
enum LivePricing: Decodable {
    case measured(markPriceUsd: Decimal, markState: String)
    case unmeasured(reason: String)

    private enum CodingKeys: String, CodingKey {
        case state, markPriceUsd, markState, reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(String.self, forKey: .state)
        if state == "measured" {
            let raw = try container.decode(String.self, forKey: .markPriceUsd)
            let markState = try container.decode(String.self, forKey: .markState)
            guard let value = Decimal(string: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .markPriceUsd, in: container, debugDescription: "bad decimal")
            }
            self = .measured(markPriceUsd: value, markState: markState)
        } else {
            let reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "unknown"
            self = .unmeasured(reason: reason)
        }
    }
}

struct LivePosition: Decodable {
    let tokenMint: String
    let pricing: LivePricing
    @OptionalDecimalString var unrealizedPnlUsd: Decimal?
    @OptionalDecimalString var unrealizedPnlPct: Decimal?
}

/// One update the server's replay buffer covered when a resume's gap wasn't a full
/// `counterReset` or `truncated` — see `LiveGap`.
struct GapReplayEntry: Decodable {
    let seq: Int
    let at: String
    let reason: String
    let changedMints: [String]
}

/// Present only on a resume tick (`reason == "resume"`), describing what happened
/// between the `sinceSeq` the client asked to resume from and this tick's `seq`.
/// `missedUpdates` is `nil` exactly when `counterReset` is `true` — the server
/// restarted and its seq counter started over from 1 underneath the client, so any
/// seq the client was holding is meaningless; treat this tick's top-level state as a
/// fresh full baseline, same as a first subscribe. `truncated: true` means the
/// server's own replay buffer didn't reach back to `fromSeq` — same treatment: this
/// tick is the new full baseline, don't try to replay `replayed` as deltas.
struct LiveGap: Decodable {
    let fromSeq: Int
    let toSeq: Int
    let missedUpdates: Int?
    let counterReset: Bool
    let replayed: [GapReplayEntry]
    let truncated: Bool
}

/// `PaperLiveTick` — pushed over the `/paper` Socket.IO namespace on subscribe/resume
/// and on every subsequent change. Every reason ('subscribe'|'resume'|'price_change'|
/// 'trade'|'heartbeat') carries this SAME full top-level state, so there's one parse
/// path and no special heartbeat handler — the top-level fields are always the
/// authoritative current snapshot, never a delta to apply. `gap` is the exception:
/// it's populated only on a resume tick, and only narrates what the client missed
/// between the `sinceSeq` it resumed from and this tick.
struct PaperLiveTick: Decodable {
    let portfolioId: String
    let seq: Int
    let reason: String
    @DecimalString var equityUsd: Decimal
    @DecimalString var cashUsd: Decimal
    @DecimalString var positionsValueUsd: Decimal
    let positions: [LivePosition]
    let heartbeatIntervalMs: Int
    let gap: LiveGap?
}

struct PaperLiveError: Decodable {
    let code: String
    let message: String
}
