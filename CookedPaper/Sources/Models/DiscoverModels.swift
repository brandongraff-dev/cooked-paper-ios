import Foundation

/// The tabs on the Discover screen. Every response is explicitly `provenance: 'PAPER
/// · UNVERIFIED'` — this feed applies almost none of the safety-gated `/discover/*`
/// surface's filters (see `PaperDiscoverResponse.guarantees` server-side), so it is
/// deliberately not presented as vetted; it is "what's active right now."
enum PaperDiscoverFeed: String, CaseIterable, Identifiable {
    case mostActive = "most_active"
    case biggestMovers = "biggest_movers"
    case newest
    case popular
    case mostHeld = "most_held"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mostActive: "Active"
        case .biggestMovers: "Movers"
        case .newest: "New"
        case .popular: "Popular"
        case .mostHeld: "Held"
        }
    }
}

struct PaperTradeableInfo: Decodable {
    let tradeable: Bool
    @DecimalString var priceUsd: Decimal
    @OptionalDecimalString var liquidityUsd: Decimal?
}

struct PaperDiscoverMetrics: Decodable {
    @OptionalDecimalString var volumeUsd: Decimal?
    @OptionalDecimalString var marketCapUsd: Decimal?
    @OptionalDecimalString var priceChangePct: Decimal?
}

struct PaperDiscoverEntry: Decodable, Identifiable {
    var id: String { mint }
    let mint: String
    let symbol: String?
    let name: String?
    let logoUri: String?
    let isVerified: Bool
    let paperTradeable: PaperTradeableInfo
    let metrics: PaperDiscoverMetrics
    let rank: Int
}

private struct PaperDiscoverPage: Decodable {
    let nextCursor: String?
    let hasMore: Bool
}

struct PaperDiscoverFeedBlock: Decodable {
    let feed: String
    let entries: [PaperDiscoverEntry]
    let page: PaperDiscoverPageInfo
}

struct PaperDiscoverPageInfo: Decodable {
    let nextCursor: String?
    let hasMore: Bool
}

struct PaperDiscoverResponse: Decodable {
    let feeds: [PaperDiscoverFeedBlock]

    func entries(for feed: PaperDiscoverFeed) -> [PaperDiscoverEntry] {
        feeds.first { $0.feed == feed.rawValue }?.entries ?? []
    }
}

struct TokenSearchResult: Decodable, Identifiable {
    var id: String { mint }
    let mint: String
    let symbol: String?
    let name: String?
    let isVerified: Bool
}

struct TokenSearchResponse: Decodable {
    let results: [TokenSearchResult]
}
