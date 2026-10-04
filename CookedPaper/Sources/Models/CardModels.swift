import Foundation

/// `GET /cards/meta/*` (packages/api-types/src/cards.ts `CardMetaResponse`), only
/// the parts the share button uses. Public, and **percentages only**: the card
/// payload has no field a dollar amount could occupy.
struct ShareCardMeta: Decodable {
    struct Model: Decodable {
        /// A token symbol or the portfolio's name, already sanitized server-side.
        let headline: String
        /// Percent units; null means not measurable (render nothing, never 0%).
        let returnPct: Double?
    }

    let model: Model
    /// The rendered PNG (what the page's `og:image` points at).
    let imageUrl: String
    /// `<web>/s/<subject path>` — the link that unfurls into the card.
    let pageUrl: String
}

/// Card subjects as URL paths (apps/api `subjectPath`): a paper position folds
/// everything ever spent on one mint in one portfolio; a paper portfolio is the
/// whole book. Always the all-time window.
enum ShareCardSubject {
    static func position(portfolioId: String, mint: String) -> String {
        "paper/position/\(portfolioId)/\(mint)/all"
    }

    static func portfolio(portfolioId: String) -> String {
        "paper/portfolio/\(portfolioId)/all"
    }
}
