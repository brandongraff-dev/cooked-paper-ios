import Foundation
import SwiftUI
import UIKit

/// What a Daily Call card shows: the streak (the flame), today's token, and your
/// call on it — or the question, when you haven't called yet.
struct DailyCallShareCardModel: Hashable {
    let streak: Int
    let best: Int
    let mint: String
    /// "$WIF".
    let symbol: String
    let logoURLString: String?
    let side: DailyCallSide?

    var logoURL: URL {
        logoURLString.flatMap(URL.init(string:)) ?? TokenAPI.logoURL(mint: mint)
    }

    /// Nil when the server has no call open today.
    init?(response: DailyCallTodayResponse) {
        guard let call = response.call else { return nil }
        self.init(
            streak: response.streak.current,
            best: response.streak.best,
            mint: call.token.mint,
            symbol: call.token.displaySymbol,
            logoURLString: call.token.logoUri,
            side: call.me?.sideKind
        )
    }

    init(streak: Int, best: Int, mint: String, symbol: String, logoURLString: String?, side: DailyCallSide?) {
        self.streak = streak
        self.best = best
        self.mint = mint
        self.symbol = symbol
        self.logoURLString = logoURLString
        self.side = side
    }

    var shareTitle: String { "Daily Call on Cooked" }

    var shareMessage: String {
        let call = side.map { "I called \(symbol) \($0.title.lowercased()) today" } ?? "Higher or lower on \(symbol) today?"
        let streakLine = streak > 0 ? " \(ShareCardFormat.streak(streak))." : ""
        return "\(call) on Cooked's Daily Call.\(streakLine) Paper game, no stakes. cooked.trade"
    }
}

/// The Daily Call card: the flame and streak big, today's token and call below.
struct DailyCallShareCard: View {
    let model: DailyCallShareCardModel
    var logo: UIImage? = nil

    var body: some View {
        ShareCardCanvas(tag: "DAILY CALL") {
            VStack(alignment: .leading, spacing: Space.s24) {
                HStack(alignment: .center, spacing: Space.s12) {
                    Image(systemName: model.streak > 0 ? "flame.fill" : "flame")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(model.streak > 0 ? AchievementTier.gold.color : Color.textTertiary)
                    Text("\(model.streak)")
                        .font(.system(size: 88, weight: .heavy).monospacedDigit())
                        .tracking(-2)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("day streak")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Best \(model.best)")
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }

                HStack(spacing: Space.s12) {
                    ShareCardTokenLogo(image: logo, symbol: model.symbol, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's token")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Text(model.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: Space.s8)
                    callBadge
                }
                .padding(Space.s16)
                .background(
                    Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                )
            }
        }
    }

    @ViewBuilder
    private var callBadge: some View {
        if let side = model.side {
            VStack(alignment: .trailing, spacing: 2) {
                Text("My call")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                HStack(spacing: 4) {
                    Image(systemName: side.symbol)
                        .font(.system(size: 16, weight: .bold))
                    Text(side.title.uppercased())
                        .font(.system(size: 20, weight: .bold))
                }
                .foregroundStyle(side == .higher ? Color.positive : Color.negative)
            }
        } else {
            Text("Higher or lower?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ShareCardStyle.glow)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// The share button for the Daily Call; shows nothing without a call today.
struct DailyCallShareButton: View {
    let response: DailyCallTodayResponse
    var compact = false

    var body: some View {
        if let model = DailyCallShareCardModel(response: response) {
            ShareImageButton(
                id: model,
                title: model.shareTitle,
                message: model.shareMessage,
                logoURL: model.logoURL,
                compact: compact,
                label: "Share streak"
            ) { logo in
                DailyCallShareCard(model: model, logo: logo)
            }
        }
    }
}

#if DEBUG
#Preview("Daily Call card · called") {
    DailyCallShareCard(
        model: DailyCallShareCardModel(
            streak: 7,
            best: 12,
            mint: "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm",
            symbol: "$WIF",
            logoURLString: nil,
            side: .higher
        )
    )
}

#Preview("Daily Call card · not called") {
    DailyCallShareCard(
        model: DailyCallShareCardModel(
            streak: 0,
            best: 3,
            mint: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
            symbol: "$BONK",
            logoURLString: nil,
            side: nil
        )
    )
}
#endif
