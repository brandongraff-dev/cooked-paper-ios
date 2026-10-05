import Foundation
import SwiftUI
import UIKit

/// What a trade card shows: one token, where you got in, where it is now (an open
/// position) or where you got out (a sell), and the return between them.
struct TradeShareCardModel: Hashable {
    let mint: String
    /// "$WIF".
    let symbol: String
    let entryPriceUsd: Decimal
    /// The mark for an open position, the fill price for a sell.
    let currentPriceUsd: Decimal
    /// A sell: label the second price "Exit" rather than "Now".
    let isClosed: Bool
    /// Percent units; nil when not measurable.
    let returnPct: Decimal?

    var logoURL: URL { TokenAPI.logoURL(mint: mint) }

    /// An open position: its average cost against the live mark, with the server's
    /// own return when it has one.
    init(position: PaperPosition) {
        mint = position.tokenMint
        symbol = ShareCardFormat.symbol(position.token?.symbol, mint: position.tokenMint)
        entryPriceUsd = position.avgCostUsd
        currentPriceUsd = position.markPriceUsd
        isClosed = false
        returnPct = position.unrealizedReturnPct
            ?? ShareCardFormat.returnPct(entry: position.avgCostUsd, exit: position.markPriceUsd)
    }

    init(mint: String, symbol: String?, entryPriceUsd: Decimal, currentPriceUsd: Decimal, isClosed: Bool) {
        self.mint = mint
        self.symbol = ShareCardFormat.symbol(symbol, mint: mint)
        self.entryPriceUsd = entryPriceUsd
        self.currentPriceUsd = currentPriceUsd
        self.isClosed = isClosed
        returnPct = ShareCardFormat.returnPct(entry: entryPriceUsd, exit: currentPriceUsd)
    }

    var shareTitle: String { "\(symbol) paper trade on Cooked" }

    var shareMessage: String {
        "\(ShareCardFormat.pnl(returnPct)) on \(symbol), paper trading on Cooked Paper. Paper money, no stakes. cooked.trade"
    }
}

/// The trade card: token, the big PnL, entry → now/exit.
struct TradeShareCard: View {
    let model: TradeShareCardModel
    var logo: UIImage? = nil

    var body: some View {
        ShareCardCanvas(tag: "PAPER TRADE") {
            VStack(alignment: .leading, spacing: Space.s24) {
                HStack(spacing: Space.s12) {
                    ShareCardTokenLogo(image: logo, symbol: model.symbol, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.symbol)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(model.isClosed ? "Sold" : "Open position")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(ShareCardFormat.pnl(model.returnPct))
                        .font(.system(size: 64, weight: .bold).monospacedDigit())
                        .tracking(-1.5)
                        .foregroundStyle(Color.direction(model.returnPct))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Return")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }

                HStack(alignment: .center, spacing: Space.s12) {
                    priceColumn(label: "Entry", value: model.entryPriceUsd)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                    priceColumn(label: model.isClosed ? "Exit" : "Now", value: model.currentPriceUsd)
                    Spacer(minLength: 0)
                }
                .padding(Space.s16)
                .background(
                    Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                )
            }
        }
    }

    private func priceColumn(label: String, value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            Text(PriceFormat.price(value))
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// The share button for a trade card.
struct TradeShareButton: View {
    let model: TradeShareCardModel
    var compact = false

    var body: some View {
        ShareImageButton(
            id: model,
            title: model.shareTitle,
            message: model.shareMessage,
            logoURL: model.logoURL,
            compact: compact,
            label: "Share trade"
        ) { logo in
            TradeShareCard(model: model, logo: logo)
        }
    }
}

#if DEBUG
#Preview("Trade card · gain") {
    TradeShareCard(
        model: TradeShareCardModel(
            mint: "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm",
            symbol: "WIF",
            entryPriceUsd: Decimal(string: "1.8423")!,
            currentPriceUsd: Decimal(string: "2.6031")!,
            isClosed: true
        )
    )
}

#Preview("Trade card · loss") {
    TradeShareCard(
        model: TradeShareCardModel(
            mint: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
            symbol: "BONK",
            entryPriceUsd: Decimal(string: "0.0000231")!,
            currentPriceUsd: Decimal(string: "0.0000189")!,
            isClosed: false
        )
    )
}
#endif
