import SwiftUI

/// Shares a server-rendered P&L card: the card's web link, which unfurls into the
/// image wherever it's pasted. Percentages only, like the card. Appears only once
/// `GET /cards/meta/…` answers, so a server without cards (or a subject it won't
/// render) simply shows no button.
struct ShareCardButton: View {
    let subjectPath: String
    /// Icon-only, for a toolbar.
    var compact = false

    @State private var meta: ShareCardMeta?

    private var returnText: String? {
        meta?.model.returnPct.map { String(format: "%+.1f%%", $0) }
    }

    private var title: String {
        guard let meta else { return "My Cooked Paper result" }
        return "\(meta.model.headline) on Cooked Paper"
    }

    private var message: String {
        let headline = meta?.model.headline ?? "My paper trade"
        if let returnText {
            return "\(headline): \(returnText) on Cooked Paper (paper trading, simulated)."
        }
        return "\(headline) on Cooked Paper (paper trading, simulated)."
    }

    var body: some View {
        Group {
            if let meta, let url = URL(string: meta.pageUrl) {
                ShareLink(item: url, subject: Text(title), message: Text(message), preview: SharePreview(title)) {
                    if compact {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Color.textPrimary)
                    } else {
                        Label("Share result", systemImage: "square.and.arrow.up")
                    }
                }
                .accessibilityLabel("Share result")
                .accessibilityIdentifier("share.card")
            }
        }
        .task(id: subjectPath) {
            meta = try? await CardsAPI.meta(subjectPath: subjectPath)
        }
    }
}
